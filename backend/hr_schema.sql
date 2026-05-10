-- ============================================================
-- JSR HR & Projekt Management Schema
-- ============================================================

-- Standorte
CREATE TABLE locations (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  name VARCHAR(100) NOT NULL,  -- 'Tirana', 'Prishtina'
  country VARCHAR(50),
  created_at TIMESTAMPTZ DEFAULT NOW()
);

INSERT INTO locations (name, country) VALUES 
  ('Tirana', 'Albanien'),
  ('Prishtina', 'Kosovo');

-- Projekte
CREATE TABLE projects (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  name VARCHAR(200) NOT NULL,  -- 'Holidaycheck', 'Giganetz'
  client_name VARCHAR(200),
  description TEXT,
  status VARCHAR(20) DEFAULT 'active',  -- active, paused, closed
  start_date DATE,
  end_date DATE,
  location_id UUID REFERENCES locations(id),
  -- Finanzen
  hourly_rate_training DECIMAL(8,2),   -- Satz während Schulung
  hourly_rate_active DECIMAL(8,2),     -- Satz wenn aktiv
  created_at TIMESTAMPTZ DEFAULT NOW()
);

INSERT INTO projects (name, client_name, status) VALUES
  ('Holidaycheck', 'Holidaycheck AG', 'active'),
  ('Giganetz', 'Giganetz GmbH', 'active');

-- Skills
CREATE TABLE skills (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  name VARCHAR(100) NOT NULL,  -- 'Inbound', 'Outbound', 'Email Support', etc.
  category VARCHAR(50),        -- 'Call Center', 'Sales', 'Tech'
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Schulungen (pro Projekt)
CREATE TABLE trainings (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  project_id UUID NOT NULL REFERENCES projects(id),
  name VARCHAR(200) NOT NULL,  -- 'Schulung 1', 'Schulung 2', 'Produktschulung'
  description TEXT,
  duration_weeks INTEGER,
  sequence INTEGER DEFAULT 1,  -- Reihenfolge im Projekt
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Mitarbeiter
CREATE TABLE employees (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  
  -- Basisdaten
  first_name VARCHAR(100) NOT NULL,
  last_name VARCHAR(100) NOT NULL,
  email VARCHAR(255),
  phone VARCHAR(50),
  
  -- Adresse
  street VARCHAR(255),
  city VARCHAR(100),
  country VARCHAR(50),
  location_id UUID REFERENCES locations(id),  -- Tirana oder Prishtina
  
  -- Position & Funktion
  position VARCHAR(100),      -- 'Agent', 'Senior Agent', 'Team Lead'
  department VARCHAR(100),    -- 'Call Center', 'Sales', 'Support'
  
  -- Kompetenzen
  language_level VARCHAR(10), -- 'B1', 'B2', 'C1', 'C2'
  writing_level VARCHAR(10),  -- 'B1', 'B2', 'C1', 'C2'
  better_phone BOOLEAN DEFAULT TRUE,   -- besser am Tel?
  better_email BOOLEAN DEFAULT FALSE,  -- besser per Mail?
  is_structured BOOLEAN DEFAULT TRUE,  -- strukturiert?
  sales_potential BOOLEAN DEFAULT FALSE,
  notes TEXT,
  
  -- Status
  status VARCHAR(30) DEFAULT 'cv_received',
  -- cv_received → in_system → presented → selected → training → active → inactive
  
  -- Gehalt
  salary_training DECIMAL(8,2),  -- Gehalt während Schulung
  salary_active DECIMAL(8,2),    -- Gehalt wenn aktiv
  
  -- Recruiting
  cv_received_at DATE,
  system_entry_at DATE,
  presented_at DATE,
  selected_at DATE,
  rejected_at DATE,
  rejection_reason TEXT,
  
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Mitarbeiter ↔ Skills (Many-to-Many)
CREATE TABLE employee_skills (
  employee_id UUID REFERENCES employees(id) ON DELETE CASCADE,
  skill_id UUID REFERENCES skills(id) ON DELETE CASCADE,
  certified_at DATE,
  PRIMARY KEY (employee_id, skill_id)
);

-- Mitarbeiter ↔ Projekte (aktive Zuweisung)
CREATE TABLE employee_projects (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  employee_id UUID NOT NULL REFERENCES employees(id) ON DELETE CASCADE,
  project_id UUID NOT NULL REFERENCES projects(id),
  
  -- Phase
  phase VARCHAR(30) NOT NULL DEFAULT 'training',
  -- training, active, paused, completed
  
  -- Schulungs-Tracking
  current_training_id UUID REFERENCES trainings(id),
  training_start_date DATE,
  training_end_date DATE,
  
  -- Aktiv-Phase
  active_start_date DATE,
  active_end_date DATE,
  
  -- Finanzen dieser Zuweisung
  hourly_rate_billed DECIMAL(8,2),  -- was wir dem Kunden berechnen
  hourly_rate_cost DECIMAL(8,2),    -- was wir dem MA zahlen
  hours_per_week DECIMAL(5,1) DEFAULT 40,
  
  notes TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Recruiting Pipeline Events (Audit-Log)
CREATE TABLE recruiting_events (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  employee_id UUID NOT NULL REFERENCES employees(id) ON DELETE CASCADE,
  event_type VARCHAR(50) NOT NULL,
  -- cv_received, system_entry, presented, selected, rejected, 
  -- training_started, training_completed, active_started, inactive
  event_date DATE NOT NULL DEFAULT CURRENT_DATE,
  project_id UUID REFERENCES projects(id),
  training_id UUID REFERENCES trainings(id),
  notes TEXT,
  created_by VARCHAR(100),
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Standard Skills anlegen
INSERT INTO skills (name, category) VALUES
  ('Inbound Telefonie', 'Call Center'),
  ('Outbound Telefonie', 'Call Center'),
  ('Email Support', 'Call Center'),
  ('Chat Support', 'Call Center'),
  ('Beschwerdemanagement', 'Call Center'),
  ('Sales Outbound', 'Sales'),
  ('Cross-Selling', 'Sales'),
  ('CRM Systeme', 'Tech'),
  ('Ticketing Systeme', 'Tech'),
  ('Reisebuchung', 'Fach'),
  ('Touristik Kenntnisse', 'Fach'),
  ('Deutsch B2+', 'Sprache'),
  ('Englisch', 'Sprache');

-- Standard Schulungen für Projekte
INSERT INTO trainings (project_id, name, sequence, duration_weeks)
SELECT id, 'Onboarding & Grundlagen', 1, 1 FROM projects WHERE name = 'Holidaycheck';
INSERT INTO trainings (project_id, name, sequence, duration_weeks)
SELECT id, 'Produktschulung Holidaycheck', 2, 2 FROM projects WHERE name = 'Holidaycheck';
INSERT INTO trainings (project_id, name, sequence, duration_weeks)
SELECT id, 'Systemschulung & Praxis', 3, 1 FROM projects WHERE name = 'Holidaycheck';

INSERT INTO trainings (project_id, name, sequence, duration_weeks)
SELECT id, 'Onboarding & Grundlagen', 1, 1 FROM projects WHERE name = 'Giganetz';
INSERT INTO trainings (project_id, name, sequence, duration_weeks)
SELECT id, 'Produktschulung Giganetz', 2, 2 FROM projects WHERE name = 'Giganetz';

-- Indices
CREATE INDEX idx_employees_status ON employees(status);
CREATE INDEX idx_employees_location ON employees(location_id);
CREATE INDEX idx_emp_projects_employee ON employee_projects(employee_id);
CREATE INDEX idx_emp_projects_project ON employee_projects(project_id);
CREATE INDEX idx_recruiting_employee ON recruiting_events(employee_id);
