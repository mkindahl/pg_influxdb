-- InfluxDB API to PostgreSQL. Copyright (C) 2025 Mats Kindahl
--
-- This program is free software: you can redistribute it and/or
-- modify it under the terms of the GNU Affero General Public License
-- as published by the Free Software Foundation, either version 3 of
-- the License, or (at your option) any later version.
--
-- This program is distributed in the hope that it will be useful, but
-- WITHOUT ANY WARRANTY; without even the implied warranty of
-- MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
-- Affero General Public License for more details.
--
-- You should have received a copy of the GNU Affero General Public
-- License along with this program.  If not, see
-- <https://www.gnu.org/licenses/>.

CREATE EXTENSION influxdb;

-- Basic percent-encoding
SELECT influxdb.url_decode('hello%20world');
SELECT influxdb.url_decode('%48%65%6C%6C%6F');

-- Plus as space
SELECT influxdb.url_decode('hello+world');
SELECT influxdb.url_decode('a+b+c');

-- Mixed encoding
SELECT influxdb.url_decode('key%3Dvalue%26foo%3Dbar');
SELECT influxdb.url_decode('CREATE+DATABASE+%22mydb%22');

-- Bare percent at end of string
SELECT influxdb.url_decode('%');

-- Truncated: percent with one hex digit
SELECT influxdb.url_decode('%f');

-- Truncated: percent with one hex digit mid-string
SELECT influxdb.url_decode('a%fb');

-- Valid two-digit hex
SELECT influxdb.url_decode('%ff');

-- Non-hex characters after percent
SELECT influxdb.url_decode('%zz');
SELECT influxdb.url_decode('%g1');

-- Empty string
SELECT influxdb.url_decode('');

-- No encoding needed
SELECT influxdb.url_decode('plaintext');

-- Percent-encoded special characters
SELECT influxdb.url_decode('%2F');
SELECT influxdb.url_decode('%3F');
SELECT influxdb.url_decode('%23');
SELECT influxdb.url_decode('%26');

-- Case insensitive hex digits
SELECT influxdb.url_decode('%2f');
SELECT influxdb.url_decode('%2F');

-- Multiple percent-encoded sequences
SELECT influxdb.url_decode('%20%20%20');

-- Percent at various positions
SELECT influxdb.url_decode('abc%');
SELECT influxdb.url_decode('abc%f');
SELECT influxdb.url_decode('%abc');
