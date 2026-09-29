CREATE OR REPLACE FUNCTION rumba_notify_exercise_change() RETURNS trigger AS $$
BEGIN
  NEW.embedding_needs_sync := TRUE;
  PERFORM pg_notify('exercise_changed', NEW.exercise_id::text);
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;
DROP TRIGGER IF EXISTS rumba_exercise_changed ON exercise;
CREATE TRIGGER rumba_exercise_changed
BEFORE INSERT OR UPDATE OF title, content ON exercise
FOR EACH ROW EXECUTE FUNCTION rumba_notify_exercise_change();
