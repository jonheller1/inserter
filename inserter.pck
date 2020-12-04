create or replace package inserter authid current_user is

--Constants used for parameters.
--(Created as functions because package variables cannot be referenced in SQL.)
function ANSI_LITERAL  return number;
function TO_DATE       return number;
function ALTER_SESSION return number;

function ALIGNED       return number;
function UNALIGNED     return number;

function UPPER         return number;
function LOWER         return number;
function CAMEL         return number;

function HEADER_ON     return number;
function HEADER_OFF    return number;

--Main function
function get_script
(
	p_table_name      varchar2,
	p_select          clob,
	p_date_style      number   default ansi_literal,
	p_nls_date_format varchar2 default null,
	p_alignment       number   default unaligned,
	p_case_style      number   default lower,
	p_header          varchar2 default header_on
) return clob;

end;
/
create or replace package body inserter is

--Store the results in a 2D array.
--TODO: Use CLOB instead, but it's much slower.
type columns_nt is table of varchar2(32767);
type rows_nt is table of columns_nt;

--Keywords, for case sensitivity.
g_insert_into         varchar2(100);
g_select              varchar2(100);
g_null                varchar2(100);
g_from_dual           varchar2(100);
g_union_all           varchar2(100);
g_timestamp           varchar2(100);
g_date                varchar2(100);
g_to_date             varchar2(100);

--Functions that act like constants.
function ANSI_LITERAL  return number is begin return 1; end;
function TO_DATE       return number is begin return 2; end;
function ALTER_SESSION return number is begin return 3; end;
function ALIGNED       return number is begin return 4; end;
function UNALIGNED     return number is begin return 5; end;
function UPPER         return number is begin return 6; end;
function LOWER         return number is begin return 7; end;
function CAMEL         return number is begin return 8; end;

function HEADER_ON     return number is begin return 9; end;
function HEADER_OFF    return number is begin return 10; end;



--------------------------------------------------------------------------------------------------------------------------
procedure verify_parameters(p_date_style number, p_nls_date_format varchar2, p_alignment number, p_case_style number) is
	v_throwaway varchar2(32767);
begin
	--Check that P_DATE_STYLE is correct.
	if p_date_style in (inserter.ansi_literal, inserter.to_date, inserter.alter_session) then
		null;
	else
		raise_application_error(-20000, 'p_date_style must be one of INSERTER.ANSI_LITERAL, INSERTER.TO_DATE, or INSERTER.ALTER_SESSION.');
	end if;

	--Check that P_DATE_STYLE and P_NLS_DATE_FORMAT are set correctly together.
	if p_date_style = inserter.ansi_literal and p_nls_date_format is not null then
		raise_application_error(-20000, 'If P_DATE_STYLE is set to ANSI_LITERAL then P_NLS_DATE_FORMAT should be null.');
	end if;

	--Check that P_DATE_STYLE and P_NLS_DATE_FORMAT are set correctly together.
	if p_date_style in (inserter.to_date, inserter.alter_session) and p_nls_date_format is null then
		raise_application_error(-20000, 'If P_DATE_STYLE is set to TO_DATE or ALTER_SESSION, then P_NLS_DATE_FORMAT cannot be null.');
	end if;

	--Check the P_NLS_DATE_FORMAT if it was set.
	begin
		v_throwaway := to_char(sysdate, p_nls_date_format);
	exception when others then
		raise_application_error(-20000, 'The value you entered for P_NLS_DATE_FORMAT is not valid. It raised this exception: '||chr(10)||
			sqlerrm);
	end;

	--Check P_ALIGNMENT.
	if p_alignment in (aligned, unaligned) then
		null;
	else
		raise_application_error(-20000, 'P_ALIGNMENT must be set to either ALIGNED or UNALIGNED.');
	end if;

	--Check P_CASE_STYLE.
	if p_case_style in (upper, lower, camel) then
		null;
	else
		raise_application_error(-20000, 'P_CASE_STYLE must be set to either UPPER, LOWER, or CAMEL.');
	end if;

end verify_parameters;


--------------------------------------------------------------------------------
procedure set_keyword_case(p_case_style number) is
begin
	if p_case_style = upper then
		g_insert_into         := 'INSERT INTO';
		g_select              := 'SELECT';
		g_null                := 'NULL';
		g_from_dual           := 'FROM DUAL';
		g_union_all           := 'UNION ALL';
		g_timestamp           := 'TIMESTAMP';
		g_date                := 'DATE';
		g_to_date             := 'TO_DATE';
	elsif p_case_style = lower then
		g_insert_into         := 'insert into';
		g_select              := 'select';
		g_null                := 'null';
		g_from_dual           := 'from dual';
		g_union_all           := 'union all';
		g_timestamp           := 'timestamp';
		g_date                := 'date';
		g_to_date             := 'to_date';
	elsif p_case_style = camel then
		g_insert_into         := 'Insert Into';
		g_select              := 'Select';
		g_null                := 'Null';
		g_from_dual           := 'From Dual';
		g_union_all           := 'Union All';
		g_timestamp           := 'Timestamp';
		g_date                := 'Date';
		g_to_date             := 'To_Date';
	end if;
end set_keyword_case;


--------------------------------------------------------------------------------
procedure add_header
(
	p_output in out nocopy clob,
	p_table_name varchar2,
	p_rows number, p_date_style number,
	p_nls_date_format varchar2,
	p_header varchar2
) is
	v_header clob;
	v_new_output clob;
begin
	if p_header = to_char(header_off) then
		null;
	elsif p_header = to_char(header_on) then
		--Add boilerplate header.
		v_header := replace(replace(replace(replace(replace(
			q'[
				------------------------------------------------------------------------
				-- Generated by #USER# on #DATE#.
				-- This script inserts #ROWS# rows into the table #TABLE#
				-- Script was generated with this command:
				-- TODO
				------------------------------------------------------------------------

				]'
		,'#USER#', user)
		,'#DATE#', to_char(sysdate, 'YYYY-MM-DD HH24:MI:SS'))
		,'#TABLE#', p_table_name)
		,'#ROWS#', p_rows)
		,chr(10)||'				', chr(10));

		--Alter the session, if requested.
		if p_date_style = inserter.alter_session then
			v_header := v_header || 'alter session set nls_date_format = '''||p_nls_date_format||''';' || chr(10);
		end if;

		--TODO: There's gotta be a better way to do this.
		v_header := substr(v_header, 2);
		dbms_lob.append(v_header, p_output);
		p_output := v_header;
	else
		v_header := p_header;
		dbms_lob.append(v_header, p_output);
		p_output := v_header;
	end if;
end add_header;

--------------------------------------------------------------------------------
function get_footer return varchar2 is
begin
	return 
	q'[
	--TODO
	]';
end get_footer;

--------------------------------------------------------------------------------
function get_with_quotes_if_necessary(p_string varchar2) return varchar2 is
	v_invalid_sql_name exception;
	v_throwaway varchar2(4000);
	pragma exception_init(v_invalid_sql_name, -44003);
begin
	v_throwaway := dbms_assert.simple_sql_name(p_string);
	return p_string;
exception when v_invalid_sql_name then
	return '"' || p_string ||'"';
end get_with_quotes_if_necessary;

--------------------------------------------------------------------------------
function get_string_from_date(p_date date, p_date_style number, p_nls_date_format varchar2) return varchar2 is
begin
	if p_date is null then
		return g_null;
	else
		if p_date_style = ansi_literal then
			--Use DATE literal if there is no time, to save space.
			if p_date = trunc(p_date) then
				return g_date || ' ''' || to_char(p_date, 'YYYY-MM-DD') || '''';
			--Use TIMESTAMP literal if necessary.
			else
				return g_timestamp || ' ''' || to_char(p_date, 'YYYY-MM-DD HH24:MI:SS') || '''';
			end if;
		elsif p_date_style = to_date then
			return g_to_date || '(''' || to_char(p_date, p_nls_date_format) || ''', ''' || p_nls_date_format || ''')';
		elsif p_date_style = alter_session then
			return '''' || to_char(p_date, p_nls_date_format) || '''';
		end if;
	end if;
end get_string_from_date;

--------------------------------------------------------------------------------
function get_string_from_number(p_number number) return varchar2 is
begin
	if p_number is null then
		return g_null;
	else
		return to_char(p_number);
	end if;
	--TODO?
end get_string_from_number;

--------------------------------------------------------------------------------
function get_string_from_varchar2(p_varchar2 varchar2) return varchar2 is
begin
	if p_varchar2 is null then
		return g_null;
	else
		--Escape quotes, add quotes around value.
		return '''' || replace(p_varchar2, '''', '''''') || '''';
	end if;
end get_string_from_varchar2;

--------------------------------------------------------------------------------
function get_string_from_nvarchar2(p_nvarchar2 varchar2) return varchar2 is
begin
	--TODO
	return p_nvarchar2;
end get_string_from_nvarchar2;



--------------------------------------------------------------------------------
procedure align_values(p_column_count number, p_rows in out nocopy rows_nt) is
	v_length number;
	v_max_length number;
begin
	for i in 1 .. p_column_count loop
		--Find the maximum size for each column.
		v_max_length := 0;
		for j in 1 .. p_rows.count loop
			v_length := length(p_rows(j)(i));
			if v_length > v_max_length then
				v_max_length := v_length;
			end if;
		end loop;

		--TODO: Right-align numbers based on the decimal point

		--Pad each value, if necessary.
		for j in 1 .. p_rows.count loop
			v_length := length(p_rows(j)(i));
			if v_length < v_max_length then
				p_rows(j)(i) := p_rows(j)(i) ||
				lpad(' ', v_max_length - v_length, ' ');
			end if;
		end loop;
	end loop;
end align_values;


--------------------------------------------------------------------------------
function get_script
(
	p_table_name      varchar2,
	p_select          clob,
	p_date_style      number   default ansi_literal,
	p_nls_date_format varchar2 default null,
	p_alignment       number   default unaligned,
	p_case_style      number   default lower,
	p_header          varchar2 default header_on
) return clob is
	v_cursor number;
	v_column_count number;
	--TODO: Use conditional compilation to support older versions?
	v_column_metadata  dbms_sql.desc_tab4;
	v_row_count number;

	v_output clob;
	v_undefined integer;


/*
dbms_types.typecode_date
dbms_types.typecode_number
dbms_types.typecode_raw
dbms_types.typecode_char
dbms_types.typecode_varchar2
dbms_types.typecode_varchar
dbms_types.typecode_mlslabel
dbms_types.typecode_blob
dbms_types.typecode_bfile
dbms_types.typecode_clob
dbms_types.typecode_cfile
dbms_types.typecode_timestamp
dbms_types.typecode_timestamp_tz
dbms_types.typecode_timestamp_ltz
dbms_types.typecode_interval_ym
dbms_types.typecode_interval_ds
dbms_types.typecode_ref
dbms_types.typecode_object
dbms_types.typecode_varray
dbms_types.typecode_table
dbms_types.typecode_namedcollection
dbms_types.typecode_opaque
dbms_types.typecode_nchar
dbms_types.typecode_nvarchar2
dbms_types.typecode_nclob
dbms_types.typecode_bfloat
dbms_types.typecode_bdouble
dbms_types.typecode_urowid
*/


	--Store the results in a 2D array.
	v_header_columns columns_nt := columns_nt();
	v_columns columns_nt;
	v_rows rows_nt := rows_nt();
	v_row clob;


	--Store individual values.
	v_date      date;
	v_number    number;
	v_varchar2  varchar2(32767);
	v_nvarchar2 nvarchar2(32767);

begin
	verify_parameters(p_date_style, p_nls_date_format, p_alignment, p_case_style);
	set_keyword_case(p_case_style);


	--Begin parsing.
	v_cursor := dbms_sql.open_cursor;
	dbms_sql.parse(v_cursor, p_select, dbms_sql.native);
	dbms_sql.describe_columns3(v_cursor, v_column_count, v_column_metadata);


	--Store column header information.
	for i in 1 .. v_column_count loop
		v_header_columns.extend();
		v_header_columns(v_header_columns.count) := v_column_metadata(i).col_name;
	end loop;


	--Define variables.
	for i in 1 .. v_column_count loop
		if v_column_metadata(i).col_type = dbms_types.typecode_date then
			dbms_sql.define_column(v_cursor, i, v_date);
		elsif v_column_metadata(i).col_type = dbms_types.typecode_number then
			dbms_sql.define_column(v_cursor, i, v_number);
		elsif v_column_metadata(i).col_type in (dbms_types.typecode_char, dbms_types.typecode_varchar2, dbms_types.typecode_varchar) then
			dbms_sql.define_column(v_cursor, i, v_varchar2, 32767);
		elsif v_column_metadata(i).col_type in (dbms_types.typecode_nchar, dbms_types.typecode_nvarchar2) then
			dbms_sql.define_column(v_cursor, i, v_nvarchar2, 32767);
		end if;

	end loop;

	--Start the execution.
	v_undefined := dbms_sql.execute(v_cursor);


	--Add each row.
	loop
		v_row_count := dbms_sql.fetch_rows(v_cursor);
		exit when v_row_count = 0;

		--Create new row entry, and new array for storing columns.
		v_rows.extend;
		v_columns := columns_nt();
		v_columns.extend(v_column_count);

		for i in 1 .. v_column_count loop
			if v_column_metadata(i).col_type = dbms_types.typecode_date then
				dbms_sql.column_value(v_cursor, i, v_date);
				v_columns(i) := get_string_from_date(v_date, p_date_style, p_nls_date_format );
			elsif v_column_metadata(i).col_type = dbms_types.typecode_number then
				dbms_sql.column_value(v_cursor, i, v_number);
				v_columns(i) := get_string_from_number(v_number);
			elsif v_column_metadata(i).col_type in (dbms_types.typecode_char, dbms_types.typecode_varchar2, dbms_types.typecode_varchar) then
				dbms_sql.column_value(v_cursor, i, v_varchar2);
				v_columns(i) := get_string_from_varchar2(v_varchar2);
			elsif v_column_metadata(i).col_type in (dbms_types.typecode_nchar, dbms_types.typecode_nvarchar2) then
				dbms_sql.column_value(v_cursor, i, v_nvarchar2);
				v_columns(i) := get_string_from_nvarchar2(v_nvarchar2);
			else
				raise_application_error(-2000, 'Unexpected type - todo');
			end if;
		end loop;

		v_rows(v_rows.count) := v_columns;
	end loop;

	--Create the initial INSERT statement: insert into table(columns)
	v_output := v_output || g_insert_into || ' ' || trim(p_table_name) || '(';

	--Add each column into a comma separated list.
	for i in 1 .. v_header_columns.count loop
		v_output := v_output || get_with_quotes_if_necessary(v_header_columns(i));
		if i <> v_header_columns.count then
			v_output := v_output || ',';
		end if;
	end loop;

	v_output := v_output || ')' || chr(10);

	--TODO: What if no rows?

	--Align values to make prettier output.
	if p_alignment = aligned then
		align_values(v_columns.count, v_rows);
	end if;

	--Create row statements.
	for i in 1 .. v_rows.count loop
		v_row := g_select || ' ';

		for j in 1 .. v_columns.count loop
			dbms_lob.append(v_row, v_rows(i)(j));
			if j <> v_columns.count then
				dbms_lob.append(v_row, ',');
			end if;
		end loop;

		v_row := v_row || ' ' || g_from_dual || case when i <> v_rows.count then ' ' || g_union_all else null end;

		if i = v_rows.count then
			v_row := v_row || ';';
		end if;

		--v_output := v_output || v_row || chr(10);
		dbms_lob.append(v_output, v_row);
		dbms_lob.append(v_output, chr(10));
	end loop;


	--Finalize.
	--dbms_lob.append(get_header(p_table_name, v_rows.count, p_date_style, p_nls_date_format, p_header), v_output);


	add_header(v_output, p_table_name, v_rows.count, p_date_style, p_nls_date_format, p_header);
	--add_footer(v_output);

	--Finalize.
	--v_output := get_header(p_table_name, v_rows.count, p_date_style, p_nls_date_format, p_header) || 
	--	v_output || get_footer;

	dbms_sql.close_cursor(v_cursor);
	--dbms_output.put_line(v_output);

	return v_output;
end;
end;
/
