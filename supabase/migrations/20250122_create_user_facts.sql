-- Create user_facts table for storing extracted personal facts about users
CREATE TABLE IF NOT EXISTS user_facts (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  category TEXT NOT NULL CHECK (category IN ('demographics', 'preferences', 'relationships', 'goals', 'context')),
  key TEXT NOT NULL,
  value TEXT NOT NULL,
  confidence FLOAT CHECK (confidence >= 0 AND confidence <= 1),
  source_message_id UUID,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW(),

  -- One fact per user per category+key combination
  UNIQUE(user_id, category, key)
);

-- Indexes for fast queries
CREATE INDEX idx_user_facts_user_id ON user_facts(user_id);
CREATE INDEX idx_user_facts_category ON user_facts(category);
CREATE INDEX idx_user_facts_updated_at ON user_facts(updated_at DESC);

-- Enable Row Level Security
ALTER TABLE user_facts ENABLE ROW LEVEL SECURITY;

-- RLS Policies
CREATE POLICY "Users can view own facts"
  ON user_facts FOR SELECT
  USING (auth.uid() = user_id);

CREATE POLICY "Users can insert own facts"
  ON user_facts FOR INSERT
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update own facts"
  ON user_facts FOR UPDATE
  USING (auth.uid() = user_id);

CREATE POLICY "Users can delete own facts"
  ON user_facts FOR DELETE
  USING (auth.uid() = user_id);

-- Add facts_extracted column to ai_chat_messages
ALTER TABLE ai_chat_messages
ADD COLUMN IF NOT EXISTS facts_extracted BOOLEAN DEFAULT FALSE,
ADD COLUMN IF NOT EXISTS facts_extraction_attempted_at TIMESTAMPTZ;

-- Index for finding unprocessed messages
CREATE INDEX idx_ai_chat_messages_facts_not_extracted
ON ai_chat_messages(user_id, facts_extracted, timestamp)
WHERE facts_extracted = FALSE;

-- Function to auto-update updated_at timestamp
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Trigger to auto-update updated_at on user_facts
CREATE TRIGGER update_user_facts_updated_at
  BEFORE UPDATE ON user_facts
  FOR EACH ROW
  EXECUTE FUNCTION update_updated_at_column();

-- Comments for documentation
COMMENT ON TABLE user_facts IS 'Stores extracted personal facts about users for AI personalization';
COMMENT ON COLUMN user_facts.category IS 'Fact category: demographics, preferences, relationships, goals, context';
COMMENT ON COLUMN user_facts.key IS 'Specific fact key (e.g., age, location, occupation)';
COMMENT ON COLUMN user_facts.value IS 'The actual fact value';
COMMENT ON COLUMN user_facts.confidence IS 'AI confidence score 0.0-1.0';
COMMENT ON COLUMN user_facts.source_message_id IS 'ID of the message this fact was extracted from';
COMMENT ON COLUMN ai_chat_messages.facts_extracted IS 'Whether facts have been extracted from this message';
COMMENT ON COLUMN ai_chat_messages.facts_extraction_attempted_at IS 'When fact extraction was last attempted';
