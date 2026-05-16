-- vets-service Flyway migration V2

INSERT INTO vets (first_name, last_name) VALUES
  ('James',  'Carter'),
  ('Helen',  'Leary'),
  ('Linda',  'Douglas'),
  ('Rafael', 'Ortega'),
  ('Henry',  'Stevens'),
  ('Sharon', 'Jenkins');

INSERT INTO specialties (name) VALUES
  ('radiology'), ('surgery'), ('dentistry');

INSERT INTO vet_specialties (vet_id, specialty_id) VALUES
  (2, 1),
  (3, 2),
  (4, 2),
  (5, 1),
  (6, 3);
