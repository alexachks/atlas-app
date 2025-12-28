-- Enable pg_net extension for HTTP requests from database
CREATE EXTENSION IF NOT EXISTS pg_net;

-- Function to trigger fact extraction when threshold is reached
CREATE OR REPLACE FUNCTION trigger_fact_extraction()
RETURNS TRIGGER AS $$
DECLARE
  unprocessed_count INT;
  edge_function_url TEXT;
  auth_token TEXT;
  request_id BIGINT;
BEGIN
  -- Only process user messages
  IF NEW.role != 'user' THEN
    RETURN NEW;
  END IF;

  -- Count unprocessed messages for this user
  SELECT COUNT(*)
  INTO unprocessed_count
  FROM ai_chat_messages
  WHERE user_id = NEW.user_id
    AND role = 'user'
    AND (facts_extracted = FALSE OR facts_extracted IS NULL);

  -- Log for debugging
  RAISE NOTICE 'User % has % unprocessed messages', NEW.user_id, unprocessed_count;

  -- Only trigger if we have 10+ unprocessed messages
  IF unprocessed_count >= 10 THEN
    RAISE NOTICE 'Triggering fact extraction for user %', NEW.user_id;

    -- Get the edge function URL (adjust this to your project)
    edge_function_url := 'https://sqchwnbwcnqegwtffxbz.supabase.co/functions/v1/extract-facts-batch';

    -- Get service role key from vault (or use anon key - we'll authenticate via RLS)
    -- For now, we'll use empty string and rely on RLS
    auth_token := '';

    -- Make async HTTP request to edge function
    -- We use pg_net to avoid blocking the INSERT
    SELECT net.http_post(
      url := edge_function_url,
      headers := jsonb_build_object(
        'Content-Type', 'application/json'
      ),
      body := jsonb_build_object(
        'user_id', NEW.user_id::text
      )
    ) INTO request_id;

    RAISE NOTICE 'Sent extraction request with ID %', request_id;
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Create trigger that fires AFTER INSERT
DROP TRIGGER IF EXISTS fact_extraction_trigger ON ai_chat_messages;

CREATE TRIGGER fact_extraction_trigger
  AFTER INSERT ON ai_chat_messages
  FOR EACH ROW
  EXECUTE FUNCTION trigger_fact_extraction();

-- Grant necessary permissions
GRANT USAGE ON SCHEMA net TO postgres, anon, authenticated, service_role;
GRANT ALL ON ALL TABLES IN SCHEMA net TO postgres, anon, authenticated, service_role;
GRANT ALL ON ALL ROUTINES IN SCHEMA net TO postgres, anon, authenticated, service_role;
GRANT ALL ON ALL SEQUENCES IN SCHEMA net TO postgres, anon, authenticated, service_role;

-- Add comment for documentation
COMMENT ON FUNCTION trigger_fact_extraction() IS
'Automatically triggers fact extraction when a user has 10+ unprocessed messages.
Calls the extract-facts-batch edge function via pg_net for async processing.';
