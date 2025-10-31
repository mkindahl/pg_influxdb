-- complain if script is sourced in psql, rather than via CREATE EXTENSION
\echo Use "CREATE EXTENSION influxdb" to load this file. \quit

CREATE FUNCTION @extschema@.parse_line(text) RETURNS jsonb AS 'MODULE_PATHNAME' LANGUAGE C;
CREATE FUNCTION @extschema@.tokenize(text) RETURNS TABLE(kind integer, value text) AS 'MODULE_PATHNAME' LANGUAGE C;
CREATE PROCEDURE @extschema@.process_line(regnamespace, text) AS 'MODULE_PATHNAME' LANGUAGE C;
