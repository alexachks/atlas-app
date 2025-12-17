-- ============================================
-- Atlas App - Supabase Database Schema
-- ============================================

-- Enable UUID extension
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- ============================================
-- PROFILES TABLE
-- ============================================
-- This table stores additional user profile information
-- It's linked to Supabase Auth's users table

CREATE TABLE IF NOT EXISTS public.profiles (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    full_name TEXT NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    UNIQUE(user_id)
);

-- Enable Row Level Security
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;

-- RLS Policies for profiles
CREATE POLICY "Users can view their own profile"
    ON public.profiles FOR SELECT
    USING (auth.uid() = user_id);

CREATE POLICY "Users can update their own profile"
    ON public.profiles FOR UPDATE
    USING (auth.uid() = user_id);

CREATE POLICY "Users can insert their own profile"
    ON public.profiles FOR INSERT
    WITH CHECK (auth.uid() = user_id);

-- ============================================
-- GOALS TABLE
-- ============================================
CREATE TABLE IF NOT EXISTS public.goals (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    title TEXT NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

ALTER TABLE public.goals ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view their own goals"
    ON public.goals FOR SELECT
    USING (auth.uid() = user_id);

CREATE POLICY "Users can create their own goals"
    ON public.goals FOR INSERT
    WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update their own goals"
    ON public.goals FOR UPDATE
    USING (auth.uid() = user_id);

CREATE POLICY "Users can delete their own goals"
    ON public.goals FOR DELETE
    USING (auth.uid() = user_id);

-- ============================================
-- TOPICS TABLE (Milestones)
-- ============================================
CREATE TABLE IF NOT EXISTS public.topics (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    goal_id UUID NOT NULL REFERENCES public.goals(id) ON DELETE CASCADE,
    title TEXT NOT NULL,
    description TEXT DEFAULT '',
    "order" INTEGER NOT NULL DEFAULT 0,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

ALTER TABLE public.topics ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view topics of their goals"
    ON public.topics FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM public.goals
            WHERE goals.id = topics.goal_id
            AND goals.user_id = auth.uid()
        )
    );

CREATE POLICY "Users can create topics for their goals"
    ON public.topics FOR INSERT
    WITH CHECK (
        EXISTS (
            SELECT 1 FROM public.goals
            WHERE goals.id = topics.goal_id
            AND goals.user_id = auth.uid()
        )
    );

CREATE POLICY "Users can update topics of their goals"
    ON public.topics FOR UPDATE
    USING (
        EXISTS (
            SELECT 1 FROM public.goals
            WHERE goals.id = topics.goal_id
            AND goals.user_id = auth.uid()
        )
    );

CREATE POLICY "Users can delete topics of their goals"
    ON public.topics FOR DELETE
    USING (
        EXISTS (
            SELECT 1 FROM public.goals
            WHERE goals.id = topics.goal_id
            AND goals.user_id = auth.uid()
        )
    );

-- ============================================
-- TASKS TABLE
-- ============================================
CREATE TABLE IF NOT EXISTS public.tasks (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    topic_id UUID NOT NULL REFERENCES public.topics(id) ON DELETE CASCADE,
    title TEXT NOT NULL,
    description TEXT DEFAULT '',
    is_completed BOOLEAN DEFAULT FALSE,
    "order" INTEGER NOT NULL DEFAULT 0,
    estimated_minutes INTEGER,
    deadline TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

ALTER TABLE public.tasks ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view tasks of their goals"
    ON public.tasks FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM public.topics
            JOIN public.goals ON goals.id = topics.goal_id
            WHERE topics.id = tasks.topic_id
            AND goals.user_id = auth.uid()
        )
    );

CREATE POLICY "Users can create tasks for their topics"
    ON public.tasks FOR INSERT
    WITH CHECK (
        EXISTS (
            SELECT 1 FROM public.topics
            JOIN public.goals ON goals.id = topics.goal_id
            WHERE topics.id = tasks.topic_id
            AND goals.user_id = auth.uid()
        )
    );

CREATE POLICY "Users can update tasks of their goals"
    ON public.tasks FOR UPDATE
    USING (
        EXISTS (
            SELECT 1 FROM public.topics
            JOIN public.goals ON goals.id = topics.goal_id
            WHERE topics.id = tasks.topic_id
            AND goals.user_id = auth.uid()
        )
    );

CREATE POLICY "Users can delete tasks of their goals"
    ON public.tasks FOR DELETE
    USING (
        EXISTS (
            SELECT 1 FROM public.topics
            JOIN public.goals ON goals.id = topics.goal_id
            WHERE topics.id = tasks.topic_id
            AND goals.user_id = auth.uid()
        )
    );

-- ============================================
-- TASK_DEPENDENCIES TABLE
-- ============================================
CREATE TABLE IF NOT EXISTS public.task_dependencies (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    task_id UUID NOT NULL REFERENCES public.tasks(id) ON DELETE CASCADE,
    depends_on_task_id UUID NOT NULL REFERENCES public.tasks(id) ON DELETE CASCADE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    UNIQUE(task_id, depends_on_task_id),
    CHECK (task_id != depends_on_task_id)
);

ALTER TABLE public.task_dependencies ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view task dependencies of their goals"
    ON public.task_dependencies FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM public.tasks
            JOIN public.topics ON topics.id = tasks.topic_id
            JOIN public.goals ON goals.id = topics.goal_id
            WHERE tasks.id = task_dependencies.task_id
            AND goals.user_id = auth.uid()
        )
    );

CREATE POLICY "Users can create task dependencies for their tasks"
    ON public.task_dependencies FOR INSERT
    WITH CHECK (
        EXISTS (
            SELECT 1 FROM public.tasks
            JOIN public.topics ON topics.id = tasks.topic_id
            JOIN public.goals ON goals.id = topics.goal_id
            WHERE tasks.id = task_dependencies.task_id
            AND goals.user_id = auth.uid()
        )
    );

CREATE POLICY "Users can delete task dependencies of their tasks"
    ON public.task_dependencies FOR DELETE
    USING (
        EXISTS (
            SELECT 1 FROM public.tasks
            JOIN public.topics ON topics.id = tasks.topic_id
            JOIN public.goals ON goals.id = topics.goal_id
            WHERE tasks.id = task_dependencies.task_id
            AND goals.user_id = auth.uid()
        )
    );

-- ============================================
-- INDEXES for better performance
-- ============================================
CREATE INDEX IF NOT EXISTS idx_profiles_user_id ON public.profiles(user_id);
CREATE INDEX IF NOT EXISTS idx_goals_user_id ON public.goals(user_id);
CREATE INDEX IF NOT EXISTS idx_topics_goal_id ON public.topics(goal_id);
CREATE INDEX IF NOT EXISTS idx_tasks_topic_id ON public.tasks(topic_id);
CREATE INDEX IF NOT EXISTS idx_tasks_is_completed ON public.tasks(is_completed);
CREATE INDEX IF NOT EXISTS idx_task_dependencies_task_id ON public.task_dependencies(task_id);
CREATE INDEX IF NOT EXISTS idx_task_dependencies_depends_on ON public.task_dependencies(depends_on_task_id);

-- ============================================
-- TRIGGERS for updated_at
-- ============================================
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER update_profiles_updated_at
    BEFORE UPDATE ON public.profiles
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_goals_updated_at
    BEFORE UPDATE ON public.goals
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_topics_updated_at
    BEFORE UPDATE ON public.topics
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_tasks_updated_at
    BEFORE UPDATE ON public.tasks
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

-- ============================================
-- SUCCESS MESSAGE
-- ============================================
DO $$
BEGIN
    RAISE NOTICE 'Atlas App database schema created successfully!';
    RAISE NOTICE 'Tables: profiles, goals, topics, tasks, task_dependencies';
    RAISE NOTICE 'RLS policies enabled for all tables';
END $$;
