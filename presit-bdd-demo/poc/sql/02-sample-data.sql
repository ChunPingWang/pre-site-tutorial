-- Seed data: meets the minimum row counts asserted in Phase 1, and matches the
-- exact George Franklin reference row that the @dml @sample-data scenario checks.

INSERT INTO types (name) VALUES
    ('cat'), ('dog'), ('lizard'), ('snake'), ('bird'), ('hamster');

INSERT INTO owners (first_name, last_name, address, telephone) VALUES
    ('George',  'Franklin',  '110 W. Liberty St.', '6085551023'),
    ('Betty',   'Davis',     '638 Cardinal Ave.',  '6085551749'),
    ('Eduardo', 'Rodriquez', '2693 Commerce St.',  '6085558763'),
    ('Harold',  'Davis',     '563 Friendly St.',   '6085553198'),
    ('Peter',   'McTavish',  '2387 S. Fair Way',   '6085552765'),
    ('Jean',    'Coleman',   '105 N. Lake St.',    '6085552654'),
    ('Jeff',    'Black',     '1450 Oak Blvd.',     '6085555387'),
    ('Maria',   'Escobito',  '345 Maple St.',      '6085557683'),
    ('David',   'Schroeder', '2749 Blackhawk Trail','6085559435'),
    ('Carlos',  'Estaban',   '2335 Independence La.','6085555487');

INSERT INTO pets (name, birth_date, type_id, owner_id) VALUES
    ('Leo',       '2010-09-07', 1, 1),
    ('Basil',     '2012-08-06', 6, 2),
    ('Rosy',      '2011-04-17', 2, 3),
    ('Jewel',     '2010-03-07', 2, 3),
    ('Iggy',      '2010-11-30', 3, 4),
    ('George',    '2010-01-20', 4, 5),
    ('Samantha',  '2012-09-04', 1, 6),
    ('Max',       '2012-09-04', 1, 6),
    ('Lucky',     '2011-08-06', 5, 7),
    ('Mulligan',  '2007-02-24', 2, 8),
    ('Freddy',    '2010-03-09', 5, 9),
    ('Lucky',     '2010-06-24', 2, 10),
    ('Sly',       '2012-06-08', 1, 10);

INSERT INTO visits (pet_id, visit_date, description) VALUES
    (7, '2013-01-01', 'rabies shot'),
    (8, '2013-01-02', 'rabies shot'),
    (8, '2013-01-03', 'neutered'),
    (7, '2013-01-04', 'spayed');

INSERT INTO vets (first_name, last_name) VALUES
    ('James',   'Carter'),
    ('Helen',   'Leary'),
    ('Linda',   'Douglas'),
    ('Rafael',  'Ortega'),
    ('Henry',   'Stevens'),
    ('Sharon',  'Jenkins');

INSERT INTO specialties (name) VALUES ('radiology'), ('surgery'), ('dentistry');

INSERT INTO vet_specialties (vet_id, specialty_id) VALUES
    (2, 1),
    (3, 2),
    (4, 2),
    (5, 1),
    (6, 3);
