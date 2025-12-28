import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from 'jsr:@supabase/supabase-js@2';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

Deno.serve(async (req: Request) => {
  const requestId = crypto.randomUUID().slice(0, 8);
  console.log(`[${requestId}] 🎤 Whisper request received: ${req.method}`);

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

    // 3. Get form data (audio file)
    console.log(`[${requestId}] 📦 Parsing multipart form data...`);
    const formData = await req.formData();
    const audioFile = formData.get('file');

    if (!audioFile || !(audioFile instanceof File)) {
      console.error(`[${requestId}] ❌ No audio file provided`);
      throw new Error('No audio file provided');
    }

    console.log(`[${requestId}] 🎵 Audio file:`, {
      name: audioFile.name,
      type: audioFile.type,
      size: audioFile.size,
      language: 'auto-detect'
    });

    // 4. Check OpenAI API key
    const openaiKey = Deno.env.get('OPENAI_API_KEY');
    if (!openaiKey) {
      console.error(`[${requestId}] ❌ OpenAI API key not configured`);
      throw new Error('OpenAI API key not configured');
    }
    console.log(`[${requestId}] ✅ OpenAI API key present`);

    // 5. Prepare FormData for OpenAI Whisper API
    const whisperFormData = new FormData();
    whisperFormData.append('file', audioFile);
    whisperFormData.append('model', 'whisper-1');
    // No language param = auto-detect original language
    whisperFormData.append('response_format', 'json');

    console.log(`[${requestId}] 📤 Sending to OpenAI Whisper API...`);

    // 6. Call OpenAI Whisper API
    const whisperResponse = await fetch('https://api.openai.com/v1/audio/transcriptions', {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${openaiKey}`,
      },
      body: whisperFormData,
    });

    console.log(`[${requestId}] 📥 Whisper response status: ${whisperResponse.status}`);

    if (!whisperResponse.ok) {
      const errorText = await whisperResponse.text();
      console.error(`[${requestId}] ❌ Whisper API error (${whisperResponse.status}):`, errorText);
      throw new Error(`Whisper API error (${whisperResponse.status}): ${errorText}`);
    }

    const transcription = await whisperResponse.json();
    console.log(`[${requestId}] ✅ Transcription successful:`, {
      textLength: transcription.text?.length ?? 0,
      text: transcription.text?.slice(0, 100) + '...'
    });

    // 7. Return transcription
    return new Response(
      JSON.stringify({
        text: transcription.text,
        requestId,
        timestamp: new Date().toISOString()
      }),
      {
        headers: {
          ...corsHeaders,
          'Content-Type': 'application/json',
        },
      }
    );
  } catch (error) {
    console.error(`[${requestId}] 💥 Error in Whisper Edge Function:`, error);
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
