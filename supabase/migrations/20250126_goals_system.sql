-- Goals System Migration: Transform from nested (Goal→Topic→Task) to flat structure
-- This enables AI to perform granular CRUD operations and enables iterative coaching

-- Goals table
CREATE TABLE goals (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  title TEXT NOT NULL,
  description TEXT,
  deadline TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Milestones table (previously called "Topics")
CREATE TABLE milestones (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  goal_id UUID NOT NULL REFERENCES goals(id) ON DELETE CASCADE,
  title TEXT NOT NULL,
  description TEXT,
  order_index INT NOT NULL,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Tasks table
CREATE TABLE tasks (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  milestone_id UUID NOT NULL REFERENCES milestones(id) ON DELETE CASCADE,
  title TEXT NOT NULL,
  description TEXT,
  is_completed BOOLEAN DEFAULT FALSE,
  deadline TIMESTAMPTZ,
  estimated_minutes INT,
  depends_on UUID[], -- array of task UUIDs that must be completed first
  order_index INT NOT NULL,
  completed_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Indexes for performance
CREATE INDEX idx_goals_user_id ON goals(user_id);
CREATE INDEX idx_milestones_goal_id ON milestones(goal_id);
CREATE INDEX idx_tasks_milestone_id ON tasks(milestone_id);
CREATE INDEX idx_tasks_completed ON tasks(is_completed);

-- RLS Policies
ALTER TABLE goals ENABLE ROW LEVEL SECURITY;
ALTER TABLE milestones ENABLE ROW LEVEL SECURITY;
ALTER TABLE tasks ENABLE ROW LEVEL SECURITY;

-- Goals: Users can only access their own goals
CREATE POLICY "Users can manage their own goals"
  ON goals FOR ALL
  USING (auth.uid() = user_id);

-- Milestones: Users can only access milestones of their goals
CREATE POLICY "Users can manage milestones of their goals"
  ON milestones FOR ALL
  USING (
    EXISTS (
      SELECT 1 FROM goals
      WHERE goals.id = milestones.goal_id
      AND goals.user_id = auth.uid()
    )
  );

-- Tasks: Users can only access tasks of their milestones
CREATE POLICY "Users can manage tasks of their milestones"
  ON tasks FOR ALL
  USING (
    EXISTS (
      SELECT 1 FROM goals
      JOIN milestones ON milestones.goal_id = goals.id
      WHERE tasks.milestone_id = milestones.id
      AND goals.user_id = auth.uid()
    )
  );

-- Updated_at trigger function
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Apply updated_at trigger to all tables
CREATE TRIGGER update_goals_updated_at
  BEFORE UPDATE ON goals
  FOR EACH ROW
  EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_milestones_updated_at
  BEFORE UPDATE ON milestones
  FOR EACH ROW
  EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_tasks_updated_at
  BEFORE UPDATE ON tasks
  FOR EACH ROW
  EXECUTE FUNCTION update_updated_at_column();

-- Comments for documentation
COMMENT ON TABLE goals IS 'User goals with title, description, and deadline';
COMMENT ON TABLE milestones IS 'Goal milestones (previously called Topics) - major steps toward completing a goal';
COMMENT ON TABLE tasks IS 'Individual tasks within milestones with dependency support';
COMMENT ON COLUMN tasks.depends_on IS 'Array of task UUIDs that must be completed before this task becomes available';
COMMENT ON COLUMN tasks.completed_at IS 'Timestamp when task was marked complete - used for completion cards in chat';
