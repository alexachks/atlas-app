import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from 'jsr:@supabase/supabase-js@2';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

Deno.serve(async (req: Request) => {
  const requestId = crypto.randomUUID().slice(0, 8);
  console.log(`[${requestId}] 🧠 Batch fact extraction request received`);

  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    // Parse request body
    const { user_id } = await req.json();

    if (!user_id) {
      throw new Error('user_id is required');
    }

    console.log(`[${requestId}] 📦 Processing batch for user: ${user_id}`);

    // Create Supabase client with service role (no RLS)
    const supabaseClient = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
    );

    // 1. Get all unprocessed user messages (oldest first)
    const { data: unprocessedMessages, error: fetchError } = await supabaseClient
      .from('ai_chat_messages')
      .select('id, content, timestamp')
      .eq('user_id', user_id)
      .eq('role', 'user')
      .or('facts_extracted.is.null,facts_extracted.eq.false')
      .order('timestamp', { ascending: true });

    if (fetchError) {
      throw new Error(`Failed to fetch messages: ${fetchError.message}`);
    }

    if (!unprocessedMessages || unprocessedMessages.length === 0) {
      console.log(`[${requestId}] ℹ️ No unprocessed messages found`);
      return new Response(
        JSON.stringify({ success: true, processedCount: 0 }),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    console.log(`[${requestId}] 📊 Found ${unprocessedMessages.length} unprocessed message(s)`);

    // 2. Build extraction prompt for Claude (batch all messages)
    const messagesText = unprocessedMessages
      .map((m: any, idx: number) => `[Message ${idx + 1}]: "${m.content}"`)
      .join('\n');

    const extractionPrompt = `You are an AI assistant that extracts important personal facts from user messages.

Analyze these user messages and extract key facts about the person:

${messagesText}

Extract facts in these categories:
1. **demographics**: age, current_location, occupation, education, nationality, gender, hometown
2. **preferences**: likes, dislikes, habits, interests, hobbies
3. **relationships**: family members, friends, colleagues, pets
4. **goals**: career aspirations, personal dreams, life goals
5. **context**: current situation, challenges, constraints, important life events

CRITICAL RULES:

**What to extract (stable facts):**
- Demographics: age, occupation, education level, nationality, hometown, current city
- Long-term preferences: favorite foods, hobbies, interests that lasted 6+ months
- Relationships: family structure, important people in their life
- Goals: clear career or life goals they want to achieve
- Context: major life events (moved countries, changed careers, graduated)
- Personal traits: work style, communication preferences, strengths/weaknesses

**IMPORTANT: Normalize and generalize facts**
- Extract the UNDERLYING TRAIT, not temporary situation
- ✅ "working on 3 projects" → \`work_style: "multitasks well"\` or \`traits: "handles multiple projects"\`
- ✅ "stressed about deadline" → \`work_style: "deadline-driven"\` (only if it's recurring pattern)
- ❌ Don't save: "working on 3 projects" (temporary situation)

**What NOT to extract (temporary states):**
- ❌ Current mood/feelings: "feeling good", "stressed today", "excited right now"
- ❌ Temporary situations: "working on a project", "having a busy week"
- ❌ Short-term plans: "going to the gym tomorrow", "meeting a friend later"
- ❌ Transient opinions: "I like this song" (unless it's a lasting preference)
- ❌ Vague statements: "doing well", "things are fine"

**Key naming conventions (use these exact keys):**
- Location: \`current_location\` (where they live now), \`hometown\` (where they're from)
- DO NOT create: previous_location, location_history, location_never_visited
- Age: \`age\` (just the number)
- Occupation: \`occupation\` or \`job_title\`
- Education: \`education_level\` (e.g., "Bachelor's degree", "High school")

**Handling updates:**
- If user says "I moved from Warsaw to San Diego":
  - Save: \`current_location: "San Diego"\`
  - Save: \`hometown: "Warsaw"\` (if it's their origin)
  - DO NOT create new keys like "previous_location"
- If user updates existing fact → use the SAME key with new value
- The database will automatically replace old values

**Examples of GOOD extractions:**
- "I'm 23 years old" → \`age: "23"\`
- "I live in San Diego" → \`current_location: "San Diego"\`
- "I'm a software engineer" → \`occupation: "software engineer"\`
- "I love playing guitar" → \`interests: "playing guitar"\`

**Examples of BAD extractions (skip these):**
- "I'm doing well" → ❌ Skip (temporary state)
- "I'm working on a project" → ❌ Skip (temporary activity)
- "I feel stressed" → ❌ Skip (current emotion)

Return ONLY valid JSON in this exact format:
{
  "facts": [
    {
      "category": "demographics",
      "key": "age",
      "value": "23",
      "confidence": 0.95,
      "reasoning": "User explicitly stated their age"
    }
  ]
}`;

    // 3. Call Claude API
    const anthropicKey = Deno.env.get('ANTHROPIC_API_KEY');
    if (!anthropicKey) {
      throw new Error('Anthropic API key not configured');
    }

    console.log(`[${requestId}] 🤖 Calling Claude API for batch extraction...`);

    const anthropicResponse = await fetch('https://api.anthropic.com/v1/messages', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'x-api-key': anthropicKey,
        'anthropic-version': '2023-06-01',
      },
      body: JSON.stringify({
        model: 'claude-sonnet-4-5-20250929',
        max_tokens: 4096,
        messages: [
          { role: 'user', content: extractionPrompt }
        ],
      }),
    });

    if (!anthropicResponse.ok) {
      const errorText = await anthropicResponse.text();
      throw new Error(`Anthropic API error (${anthropicResponse.status}): ${errorText}`);
    }

    const claudeData = await anthropicResponse.json();
    const responseText = claudeData.content[0].text;

    console.log(`[${requestId}] 📝 Claude response received`);

    // 4. Parse JSON from Claude's response
    let extracted: any;

    const jsonMatch = responseText.match(/\{[\s\S]*\}/);
    if (!jsonMatch) {
      console.warn(`[${requestId}] ⚠️ No JSON found in Claude response, returning empty facts`);
      extracted = { facts: [] };
    } else {
      try {
        extracted = JSON.parse(jsonMatch[0]);
      } catch (parseError) {
        console.error(`[${requestId}] ❌ Failed to parse JSON:`, parseError);
        extracted = { facts: [] };
      }
    }

    const validFacts = (extracted.facts || []).filter((fact: any) => {
      const validCategories = ['demographics', 'preferences', 'relationships', 'goals', 'context'];
      return fact.category && validCategories.includes(fact.category) && fact.key && fact.value;
    });

    console.log(`[${requestId}] ✅ Extracted ${validFacts.length} valid fact(s)`);

    // 5. Save facts to database (upsert)
    let savedCount = 0;
    for (const fact of validFacts) {
      try {
        await supabaseClient
          .from('user_facts')
          .upsert({
            user_id: user_id,
            category: fact.category,
            key: fact.key,
            value: fact.value,
            confidence: fact.confidence || 0.8,
            source_message_id: unprocessedMessages[0]?.id, // Reference first message
          });

        savedCount++;
        console.log(`[${requestId}] 💾 Saved: ${fact.key} = ${fact.value}`);
      } catch (saveError) {
        console.error(`[${requestId}] ❌ Failed to save fact:`, saveError);
      }
    }

    // 6. Mark ALL processed messages as extracted
    const messageIds = unprocessedMessages.map((m: any) => m.id);
    await supabaseClient
      .from('ai_chat_messages')
      .update({
        facts_extracted: true,
        facts_extraction_attempted_at: new Date().toISOString(),
      })
      .in('id', messageIds);

    console.log(`[${requestId}] ✅ Marked ${messageIds.length} message(s) as processed`);

    // 7. Return success response
    return new Response(
      JSON.stringify({
        success: true,
        factsExtracted: savedCount,
        messagesProcessed: messageIds.length,
        facts: validFacts.map((f: any) => ({
          category: f.category,
          key: f.key,
          value: f.value,
          confidence: f.confidence,
        })),
      }),
      {
        headers: {
          ...corsHeaders,
          'Content-Type': 'application/json',
        },
      }
    );

  } catch (error) {
    console.error(`[${requestId}] 💥 Error:`, error);

    return new Response(
      JSON.stringify({
        error: error.message,
        requestId,
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
