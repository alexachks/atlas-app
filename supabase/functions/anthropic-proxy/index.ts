import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from 'jsr:@supabase/supabase-js@2';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

Deno.serve(async (req: Request) => {
  const requestId = crypto.randomUUID().slice(0, 8);
  console.log(`[${requestId}] 🌐 Request received: ${req.method}`);

  if (req.method === 'OPTIONS') {
    console.log(`[${requestId}] ✅ OPTIONS request - returning CORS headers`);
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    // 1. Check Authorization header
    const authHeader = req.headers.get('Authorization');
    console.log(`[${requestId}] 🔑 Auth header present: ${!!authHeader}`);

    if (!authHeader) {
      console.error(`[${requestId}] ❌ Missing authorization header`);
      throw new Error('Missing authorization header');
    }

    // 2. Create Supabase client and verify user
    const supabaseClient = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_ANON_KEY') ?? '',
      { global: { headers: { Authorization: authHeader } } }
    );

    console.log(`[${requestId}] 🔐 Verifying user...`);
    const { data: { user }, error: authError } = await supabaseClient.auth.getUser();

    if (authError) {
      console.error(`[${requestId}] ❌ Auth error:`, authError);
      throw new Error(`Auth error: ${authError.message}`);
    }

    if (!user) {
      console.error(`[${requestId}] ❌ No user found`);
      throw new Error('Unauthorized - no user');
    }

    console.log(`[${requestId}] ✅ User verified: ${user.id}`);

    // 3. Parse request body
    console.log(`[${requestId}] 📦 Parsing request body...`);
    let requestBody;
    try {
      requestBody = await req.json();
    } catch (parseError) {
      console.error(`[${requestId}] ❌ Failed to parse JSON:`, parseError);
      throw new Error(`Invalid JSON in request body: ${parseError.message}`);
    }

    const {
      messages,
      tools,
      system,
      model = 'claude-sonnet-4-5-20250929',
      max_tokens = 8192,
      stream = false,
      userMessageId,
      userMessageContent
    } = requestBody;

    console.log(`[${requestId}] 📊 Request params:`, {
      messagesCount: messages?.length ?? 0,
      toolsCount: tools?.length ?? 0,
      systemLength: system?.length ?? 0,
      model,
      max_tokens,
      stream,
      hasUserMessageId: !!userMessageId,
      hasUserMessageContent: !!userMessageContent
    });

    // 4. Validate required fields
    if (!messages || !Array.isArray(messages)) {
      console.error(`[${requestId}] ❌ Invalid messages:`, messages);
      throw new Error('messages must be an array');
    }

    if (messages.length === 0) {
      console.error(`[${requestId}] ❌ Empty messages array`);
      throw new Error('messages array cannot be empty');
    }

    // Log first and last message for debugging
    console.log(`[${requestId}] 💬 First message:`, JSON.stringify(messages[0]).slice(0, 200));
    console.log(`[${requestId}] 💬 Last message:`, JSON.stringify(messages[messages.length - 1]).slice(0, 200));

    if (tools) {
      console.log(`[${requestId}] 🔧 Tools provided:`, tools.map((t: any) => t.name));
    }

    // 5. Check Anthropic API key
    const anthropicKey = Deno.env.get('ANTHROPIC_API_KEY');
    if (!anthropicKey) {
      console.error(`[${requestId}] ❌ Anthropic API key not configured`);
      throw new Error('Anthropic API key not configured');
    }
    console.log(`[${requestId}] ✅ Anthropic API key present`);

    // 6. Prepare Anthropic API request
    const anthropicPayload = {
      model,
      max_tokens,
      system,
      messages,
      tools,
      stream: stream ? true : false,
    };

    console.log(`[${requestId}] 📤 Sending to Anthropic API...`);
    console.log(`[${requestId}] 📋 Payload size: ${JSON.stringify(anthropicPayload).length} bytes`);

    // If streaming is requested
    if (stream) {
      console.log(`[${requestId}] 🌊 Starting streaming mode...`);

      const anthropicResponse = await fetch('https://api.anthropic.com/v1/messages', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'x-api-key': anthropicKey,
          'anthropic-version': '2023-06-01',
        },
        body: JSON.stringify(anthropicPayload),
      });

      console.log(`[${requestId}] 📥 Anthropic response status: ${anthropicResponse.status}`);

      if (!anthropicResponse.ok) {
        const errorText = await anthropicResponse.text();
        console.error(`[${requestId}] ❌ Anthropic API error (${anthropicResponse.status}):`, errorText.slice(0, 500));
        throw new Error(`Anthropic API error (${anthropicResponse.status}): ${errorText}`);
      }

      console.log(`[${requestId}] ✅ Streaming response OK, creating passthrough...`);

      // Create a passthrough stream
      const encoder = new TextEncoder();
      let accumulatedContent = '';
      let assistantMessageId = crypto.randomUUID();
      let hasToolUse = false;
      let eventCount = 0;

      const stream = new ReadableStream({
        async start(controller) {
          try {
            const reader = anthropicResponse.body?.getReader();
            if (!reader) {
              throw new Error('No response body');
            }

            const decoder = new TextDecoder();
            while (true) {
              const { done, value } = await reader.read();
              if (done) {
                console.log(`[${requestId}] ✅ Stream finished. Events: ${eventCount}, Content length: ${accumulatedContent.length}`);
                break;
              }

              const chunk = decoder.decode(value, { stream: true });
              const lines = chunk.split('\n');

              for (const line of lines) {
                if (line.startsWith('data: ')) {
                  const data = line.slice(6);
                  if (data === '[DONE]') continue;

                  try {
                    const parsed = JSON.parse(data);
                    const eventType = parsed.type;
                    eventCount++;

                    if (eventCount % 10 === 0) {
                      console.log(`[${requestId}] 📊 Processed ${eventCount} events...`);
                    }

                    if (eventType === 'content_block_delta') {
                      if (parsed.delta?.type === 'text_delta') {
                        accumulatedContent += parsed.delta.text;
                      }
                    } else if (eventType === 'content_block_start') {
                      if (parsed.content_block?.type === 'tool_use') {
                        hasToolUse = true;
                        console.log(`[${requestId}] 🔧 Tool use detected: ${parsed.content_block.name}`);
                      }
                    } else if (eventType === 'message_stop') {
                      console.log(`[${requestId}] 🛑 Message stop. Tool use: ${hasToolUse}, Content length: ${accumulatedContent.length}`);
                    }
                  } catch (e) {
                    console.warn(`[${requestId}] ⚠️ Failed to parse event JSON:`, e);
                  }
                }

                // Forward the line to client
                controller.enqueue(encoder.encode(line + '\n'));
              }
            }

            // Save assistant message to database after streaming completes
            if (userMessageId && user) {
              // Always use accumulated content - client handles tool use UI
              const finalContent = accumulatedContent || 'Создаю план...';

              console.log(`[${requestId}] 💾 Saving assistant message to DB...`);
              console.log(`[${requestId}] 📝 Content length: ${finalContent.length}, hasToolUse: ${hasToolUse}`);
              try {
                await supabaseClient
                  .from('ai_chat_messages')
                  .insert({
                    id: assistantMessageId,
                    user_id: user.id,
                    role: 'assistant',
                    content: finalContent,
                    timestamp: new Date().toISOString(),
                  });
                console.log(`[${requestId}] ✅ Assistant message saved`);
              } catch (dbError) {
                console.error(`[${requestId}] ❌ Failed to save assistant message:`, dbError);
              }
            }

            controller.close();
          } catch (error) {
            console.error(`[${requestId}] ❌ Stream error:`, error);
            controller.error(error);
          }
        },
      });

      // Save user message to database
      if (userMessageId && userMessageContent && user) {
        console.log(`[${requestId}] 💾 Saving user message to DB...`);
        try {
          await supabaseClient
            .from('ai_chat_messages')
            .insert({
              id: userMessageId,
              user_id: user.id,
              role: 'user',
              content: userMessageContent,
              timestamp: new Date().toISOString(),
            });
          console.log(`[${requestId}] ✅ User message saved`);
        } catch (dbError) {
          console.error(`[${requestId}] ❌ Failed to save user message:`, dbError);
        }
      }

      console.log(`[${requestId}] 🎉 Returning streaming response`);
      return new Response(stream, {
        headers: {
          ...corsHeaders,
          'Content-Type': 'text/event-stream',
          'Cache-Control': 'no-cache',
          'Connection': 'keep-alive',
        },
      });
    }

    // Non-streaming fallback
    console.log(`[${requestId}] 📨 Non-streaming mode...`);
    const anthropicResponse = await fetch('https://api.anthropic.com/v1/messages', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'x-api-key': anthropicKey,
        'anthropic-version': '2023-06-01',
      },
      body: JSON.stringify(anthropicPayload),
    });

    console.log(`[${requestId}] 📥 Anthropic response status: ${anthropicResponse.status}`);

    if (!anthropicResponse.ok) {
      const errorText = await anthropicResponse.text();
      console.error(`[${requestId}] ❌ Anthropic API error (${anthropicResponse.status}):`, errorText.slice(0, 500));
      throw new Error(`Anthropic API error (${anthropicResponse.status}): ${errorText}`);
    }

    const data = await anthropicResponse.json();
    console.log(`[${requestId}] ✅ Non-streaming response received`);

    return new Response(JSON.stringify(data), {
      headers: {
        ...corsHeaders,
        'Content-Type': 'application/json',
      },
    });
  } catch (error) {
    console.error(`[${requestId}] 💥 Error in Edge Function:`, error);
    console.error(`[${requestId}] 💥 Error stack:`, error.stack);

    return new Response(
      JSON.stringify({
        error: error.message,
        requestId,
        timestamp: new Date().toISOString()
      }),
      {
        status: 400,
        headers: {
          ...corsHeaders,
          'Content-Type': 'application/json',
        },
      }
    );
  }
});
