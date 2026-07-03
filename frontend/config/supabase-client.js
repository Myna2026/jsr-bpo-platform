// TIVE 360° — initialisierter Supabase-Client
// Von den Portalen importieren: import { supabase } from './config/supabase-client.js';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { SUPABASE_URL, SUPABASE_PUBLISHABLE_KEY } from './supabase-config.js';

export const supabase = createClient(SUPABASE_URL, SUPABASE_PUBLISHABLE_KEY);
