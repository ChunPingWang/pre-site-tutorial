-- customers-service Flyway migration V2: 種子資料
-- 對齊 upstream HSQLDB data.sql + v2.1 Phase 1 期望筆數

INSERT INTO types (name) VALUES
  ('cat'), ('dog'), ('lizard'), ('snake'), ('bird'), ('hamster');

INSERT INTO owners (first_name, last_name, address, city, telephone) VALUES
  ('George',  'Franklin',  '110 W. Liberty St.',     'Madison',     '6085551023'),
  ('Betty',   'Davis',     '638 Cardinal Ave.',      'Sun Prairie', '6085551749'),
  ('Eduardo', 'Rodriquez', '2693 Commerce St.',      'McFarland',   '6085558763'),
  ('Harold',  'Davis',     '563 Friendly St.',       'Windsor',     '6085553198'),
  ('Peter',   'McTavish',  '2387 S. Fair Way',       'Madison',     '6085552765'),
  ('Jean',    'Coleman',   '105 N. Lake St.',        'Monona',      '6085552654'),
  ('Jeff',    'Black',     '1450 Oak Blvd.',         'Monona',      '6085555387'),
  ('Maria',   'Escobito',  '345 Maple St.',          'Madison',     '6085557683'),
  ('David',   'Schroeder', '2749 Blackhawk Trail',   'Madison',     '6085559435'),
  ('Carlos',  'Estaban',   '2335 Independence La.',  'Waunakee',    '6085555487');

INSERT INTO pets (name, birth_date, type_id, owner_id) VALUES
  ('Leo',      '2010-09-07', 1, 1),
  ('Basil',    '2012-08-06', 6, 2),
  ('Rosy',     '2011-04-17', 2, 3),
  ('Jewel',    '2010-03-07', 2, 3),
  ('Iggy',     '2010-11-30', 3, 4),
  ('George',   '2010-01-20', 4, 5),
  ('Samantha', '2012-09-04', 1, 6),
  ('Max',      '2012-09-04', 1, 6),
  ('Lucky',    '2011-08-06', 5, 7),
  ('Mulligan', '2007-02-24', 2, 8),
  ('Freddy',   '2010-03-09', 5, 9),
  ('Lucky',    '2010-06-24', 2, 10),
  ('Sly',      '2012-06-08', 1, 10);
