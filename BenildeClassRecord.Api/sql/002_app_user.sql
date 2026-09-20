-- Benilde ClassRecord: a separate database account for the API.
--
-- XAMPP's "root" account has no password and can change every database on
-- the server. The API only needs to read and write benilde_classrecord, so it
-- should sign in with its own account that can do exactly that.
--
-- How to run: open phpMyAdmin (http://localhost/phpmyadmin), click the SQL
-- tab, replace CHANGE-THIS-PASSWORD below with a strong password, paste the
-- whole file and click Go.

CREATE USER IF NOT EXISTS 'classrecord_app'@'localhost' IDENTIFIED BY 'CHANGE-THIS-PASSWORD';

-- Everything inside benilde_classrecord only (including creating tables, so
-- that migrations still run). No access to any other database.
GRANT ALL PRIVILEGES ON benilde_classrecord.* TO 'classrecord_app'@'localhost';

FLUSH PRIVILEGES;

-- Then add this to appsettings.Local.json (same password as above):
--
--   "ConnectionStrings": {
--     "Default": "server=127.0.0.1;port=3306;database=benilde_classrecord;user=classrecord_app;password=CHANGE-THIS-PASSWORD;TreatTinyAsBoolean=true"
--   }