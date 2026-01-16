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

-- complain if script is sourced in psql, rather than via CREATE EXTENSION
\echo Use "CREATE EXTENSION influxdb" to load this file. \quit

CREATE FUNCTION @extschema@.parse_line(text) RETURNS SETOF jsonb AS 'MODULE_PATHNAME' LANGUAGE C;
CREATE FUNCTION @extschema@.tokenize(text) RETURNS TABLE(kind integer, value text) AS 'MODULE_PATHNAME' LANGUAGE C;
CREATE PROCEDURE @extschema@.process_text(regnamespace, text) AS 'MODULE_PATHNAME' LANGUAGE C;
