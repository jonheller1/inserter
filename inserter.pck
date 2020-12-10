create or replace package inserter authid current_user is

--Constants used for parameters.
--(Created as functions because package variables cannot be referenced in SQL.)
function DATE_STYLE_ANSI_LITERAL        return number;
function DATE_STYLE_TO_DATE             return number;
function DATE_STYLE_ALTER_SESSION       return number;

function ALIGNMENT_UNALIGNED            return number;
function ALIGNMENT_ALIGNED              return number;

function CASE_UPPER                     return number;
function CASE_LOWER                     return number;
function CASE_CAMEL                     return number;

function HEADER_ON                      return number;
function HEADER_OFF                     return number;
function HEADER_CUSTOM                  return number;

function INSERT_STYLE_UNION_ALL         return number;
function INSERT_STYLE_INSERT_ALL        return number;
function INSERT_STYLE_VALUES            return number;
function INSERT_STYLE_VALUES_PLSQLBLOCK return number;

function BATCH_SIZE_ALL                 return number;

function COMMIT_STYLE_AT_END            return number;
function COMMIT_STYLE_NONE              return number;
function COMMIT_STYLE_PER_BATCH         return number;

--Main function
function get_script
(
	p_table_name          varchar2,
	p_select              clob,
	p_date_style          number   default date_style_ansi_literal,
	p_nls_date_format     varchar2 default null,
	p_alignment           number   default alignment_unaligned,
	p_case_style          number   default case_lower,
	p_header              number   default header_on,
	p_header_custom_value varchar2 default null,
	p_sql_terminator      varchar2 default ';',
	p_plsql_terminator    varchar2 default chr(10)||'/',
	p_insert_style        number default insert_style_union_all,
	p_batch_size          number default 100,
	p_commit_style        number default commit_style_at_end
) return clob;

end;
/
create or replace package body inserter is

--Store the results in a 2D array.
--TODO: Use CLOB instead, but it's much slower.
type columns_nt is table of varchar2(32767);
type rows_nt is table of columns_nt;

--Keywords, listed like this to simplify case sensitivity.
g_insert_into         varchar2(100) := 'insert into';
g_insert_all          varchar2(100) := 'insert all';
g_into                varchar2(100) := 'into';
g_values              varchar2(100) := 'values';
g_select              varchar2(100) := 'select';
g_null                varchar2(100) := 'null';
g_from_dual           varchar2(100) := 'from dual';
g_union_all           varchar2(100) := 'union all';
g_timestamp           varchar2(100) := 'timestamp';
g_date                varchar2(100) := 'date';
g_to_date             varchar2(100) := 'to_date';

--Functions that act like constants.
function DATE_STYLE_ANSI_LITERAL        return number is begin return 1; end;
function DATE_STYLE_TO_DATE             return number is begin return 2; end;
function DATE_STYLE_ALTER_SESSION       return number is begin return 3; end;

function ALIGNMENT_UNALIGNED            return number is begin return 5; end;
function ALIGNMENT_ALIGNED              return number is begin return 4; end;

function CASE_LOWER                     return number is begin return 7; end;
function CASE_UPPER                     return number is begin return 6; end;
function CASE_CAMEL                     return number is begin return 8; end;

function HEADER_ON                      return number is begin return 9; end;
function HEADER_OFF                     return number is begin return 10; end;
function HEADER_CUSTOM                  return number is begin return 11; end;

function INSERT_STYLE_UNION_ALL         return number is begin return 12; end;
function INSERT_STYLE_INSERT_ALL        return number is begin return 13; end;
function INSERT_STYLE_VALUES            return number is begin return 14; end;
function INSERT_STYLE_VALUES_PLSQLBLOCK return number is begin return 15; end;

function BATCH_SIZE_ALL                 return number is begin return 16; end;

function COMMIT_STYLE_AT_END            return number is begin return 17; end;
function COMMIT_STYLE_NONE              return number is begin return 18; end;
function COMMIT_STYLE_PER_BATCH         return number is begin return 19; end;


--------------------------------------------------------------------------------------------------------------------------
procedure verify_parameters(p_date_style number, p_nls_date_format varchar2, p_alignment number, p_case_style number,
	p_header number, p_header_custom_value varchar2, p_insert_style number, p_batch_size number, p_commit_style number
) is
	v_throwaway varchar2(32767);
begin
	--Check that P_DATE_STYLE is correct.
	if p_date_style in (inserter.date_style_ansi_literal, inserter.date_style_to_date, inserter.date_style_alter_session) then
		null;
	else
		raise_application_error(-20000, 'p_date_style must be one of INSERTER.ANSI_LITERAL, INSERTER.TO_DATE, or INSERTER.ALTER_SESSION.');
	end if;

	--Check that P_DATE_STYLE and P_NLS_DATE_FORMAT are set correctly together.
	if p_date_style = inserter.date_style_ansi_literal and p_nls_date_format is not null then
		raise_application_error(-20000, 'If P_DATE_STYLE is set to ANSI_LITERAL then P_NLS_DATE_FORMAT should be null.');
	end if;

	--Check that P_DATE_STYLE and P_NLS_DATE_FORMAT are set correctly together.
	if p_date_style in (inserter.date_style_to_date, inserter.date_style_alter_session) and p_nls_date_format is null then
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
	if p_alignment in (alignment_aligned, alignment_unaligned) then
		null;
	else
		raise_application_error(-20000, 'P_ALIGNMENT must be set to either ALIGNED or UNALIGNED.');
	end if;

	--Check P_CASE_STYLE.
	if p_case_style in (case_upper, case_lower, case_camel) then
		null;
	else
		raise_application_error(-20000, 'P_CASE_STYLE must be set to either UPPER, LOWER, or CAMEL.');
	end if;

	--TODO:
	--p_header, p_header_custom_value, p_insert_style, p_batch_size, p_commit_style


end verify_parameters;


--------------------------------------------------------------------------------
procedure set_keyword_case(p_case_style number) is
begin
	--Lower is the default, set upper and camel case if necessary.
	if p_case_style = case_upper then
		g_insert_into := upper(g_insert_into);
		g_insert_all  := upper(g_insert_all);
		g_into        := upper(g_into);
		g_values      := upper(g_values);
		g_select      := upper(g_select);
		g_null        := upper(g_null);
		g_from_dual   := upper(g_from_dual);
		g_union_all   := upper(g_union_all);
		g_timestamp   := upper(g_timestamp);
		g_date        := upper(g_date);
		g_to_date     := upper(g_to_date);
	elsif p_case_style = case_camel then
		g_insert_into := initcap(g_insert_into);
		g_insert_all  := initcap(g_insert_all);
		g_into        := initcap(g_into);
		g_values      := initcap(g_values);
		g_select      := initcap(g_select);
		g_null        := initcap(g_null);
		g_from_dual   := initcap(g_from_dual);
		g_union_all   := initcap(g_union_all);
		g_timestamp   := initcap(g_timestamp);
		g_date        := initcap(g_date);
		g_to_date     := initcap(g_to_date);
	end if;
end set_keyword_case;


--------------------------------------------------------------------------------
procedure define_variables(p_column_count number, p_column_metadata dbms_sql.desc_tab4, p_cursor number) is
	v_date date;
	v_number number;
	v_varchar2 varchar2(32767);
	v_nvarchar2 nvarchar2(32767);
begin
	--Define variables.
	for i in 1 .. p_column_count loop
		if p_column_metadata(i).col_type = dbms_types.typecode_date then
			dbms_sql.define_column(p_cursor, i, v_date);
		elsif p_column_metadata(i).col_type = dbms_types.typecode_number then
			dbms_sql.define_column(p_cursor, i, v_number);
		elsif p_column_metadata(i).col_type in (dbms_types.typecode_char, dbms_types.typecode_varchar2, dbms_types.typecode_varchar) then
			dbms_sql.define_column(p_cursor, i, v_varchar2, 32767);
		elsif p_column_metadata(i).col_type in (dbms_types.typecode_nchar, dbms_types.typecode_nvarchar2) then
			dbms_sql.define_column(p_cursor, i, v_nvarchar2, 32767);
		--TODO: Add other types here.
		end if;
	end loop;
end define_variables;




--------------------------------------------------------------------------------
procedure add_header
(
	p_output in out nocopy clob,
	p_table_name varchar2,
	p_rows number, p_date_style number,
	p_nls_date_format varchar2,
	p_header varchar2,
	p_header_custom_value varchar2
) is
	v_header clob;
begin
	if p_header = header_off then
		null;
	elsif p_header = header_on then
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
		if p_date_style = inserter.date_style_alter_session then
			v_header := v_header || 'alter session set nls_date_format = '''||p_nls_date_format||''';' || chr(10);
		end if;

		--TODO: There's gotta be a better way to do this.
		v_header := substr(v_header, 2);
		dbms_lob.append(v_header, p_output);
		p_output := v_header;
	else
		v_header := p_header_custom_value;
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
		if p_date_style = DATE_STYLE_ANSI_LITERAL then
			--Use DATE literal if there is no time, to save space.
			if p_date = trunc(p_date) then
				return g_date || ' ''' || to_char(p_date, 'YYYY-MM-DD') || '''';
			--Use TIMESTAMP literal if necessary.
			else
				return g_timestamp || ' ''' || to_char(p_date, 'YYYY-MM-DD HH24:MI:SS') || '''';
			end if;
		elsif p_date_style = date_style_to_date then
			return g_to_date || '(''' || to_char(p_date, p_nls_date_format) || ''', ''' || p_nls_date_format || ''')';
		elsif p_date_style = date_style_alter_session then
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
procedure align_values(p_alignment number, p_column_count number, p_rows in out nocopy rows_nt) is
	v_length number;
	v_max_length number;
begin
	if p_alignment = alignment_aligned then
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
	end if;
end align_values;


--------------------------------------------------------------------------------
function get_column_expression(v_header_columns columns_nt) return clob is
	v_expression clob;
begin
	--TODO: Use paramter to determine where to get value?

	--Add each column into a comma separated list.
	for i in 1 .. v_header_columns.count loop
		v_expression := v_expression || get_with_quotes_if_necessary(v_header_columns(i));
		if i <> v_header_columns.count then
			v_expression := v_expression || ',';
		end if;
	end loop;

	--Always used with parentheses, if there are any values.
	if v_expression is not null then
		v_expression := '(' || v_expression || ')';
	end if;

	return v_expression;
end get_column_expression;


--------------------------------------------------------------------------------
function get_rows_from_sql
(
	v_column_count number,
	v_cursor number,
	v_column_metadata dbms_sql.desc_tab4,
	p_date_style number,
	p_nls_date_format varchar2
) return rows_nt is
	v_rows rows_nt := rows_nt();
	v_row_count number;

	--Store the results in a 2D array.
	v_columns columns_nt;

	--Store individual values.
	v_date      date;
	v_number    number;
	v_varchar2  varchar2(32767);
	v_nvarchar2 nvarchar2(32767);

begin
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
				v_columns(i) := get_string_from_date(v_date, p_date_style, p_nls_date_format);

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
				raise_application_error(-20000, 'Unexpected type - not yet implemented.');
			end if;
		end loop;

		v_rows(v_rows.count) := v_columns;
	end loop;

	return v_rows;
end get_rows_from_sql;


--------------------------------------------------------------------------------
function get_clob_from_arrays
(
	p_table_name        varchar2,
	p_column_expression clob,
	v_column_count      number,
	v_rows              rows_nt,
	p_sql_terminator    varchar2,
	p_plsql_terminator  varchar2,
	p_insert_style      number,
	p_batch_size        number,
	p_commit_style      number
) return clob is
	v_values_expression clob;
	v_output clob;
	v_row clob;


	procedure add_values(i number) is
	begin
		for j in 1 .. v_column_count loop
			dbms_lob.append(v_row, v_rows(i)(j));
			if j <> v_column_count then
				dbms_lob.append(v_row, ',');
			end if;
		end loop;
	end add_values;

	procedure end_batch(i number) is
	begin
		if i = v_rows.count or mod(i, p_batch_size) = 0 then
			v_row := v_row || p_sql_terminator;

			if i = v_rows.count and p_commit_style in (commit_style_at_end, commit_style_per_batch) then
				v_row := v_row || chr(10) || 'commit' || p_sql_terminator;
			elsif p_commit_style = commit_style_per_batch then
				v_row := v_row || chr(10) || 'commit' || p_sql_terminator;
			end if;
		--Or end just the row.
		else
			if p_insert_style = insert_style_union_all then
				v_row := v_row || ' ' || g_union_all;
			elsif p_insert_style = insert_style_insert_all then
				null;
			--TODO: Other styles
			end if;
		end if;
	end end_batch;

begin
	dbms_lob.createtemporary(v_output, true);

	--TODO: What if no rows?

	--Create row statements.
	for i in 1 .. v_rows.count loop
		v_row := null;

		if p_insert_style = insert_style_union_all then
			--Start a batch.
			if i = 1 or mod(i-1, p_batch_size) = 0 then
				v_row := g_insert_into || ' ' || trim(p_table_name) || p_column_expression || chr(10);
			end if;

			--Fill out a row.
			v_row := v_row || g_select || ' ';
			add_values(i);
			v_row := v_row || ' ' || g_from_dual;

			--End a batch.
			end_batch(i);
		elsif p_insert_style = insert_style_insert_all then
			--Start a batch.
			if i = 1 or mod(i-1, p_batch_size) = 0 then
				v_row := g_insert_all || chr(10);
			end if;

			--Fill out a row.
			v_row := v_row || g_into || ' ' || trim(p_table_name) || p_column_expression || ' ' || g_values || '(';
			add_values(i);

			--End a batch.
			v_row := v_row || ')';
			end_batch(i);
		end if;

		--TODO: Add other styles

		--v_output := v_output || v_row || chr(10);
		dbms_lob.append(v_output, v_row);
		dbms_lob.append(v_output, chr(10));
	end loop;

	return v_output;
end get_clob_from_arrays;


--------------------------------------------------------------------------------
function get_script
(
	p_table_name          varchar2,
	p_select              clob,
	p_date_style          number   default date_style_ansi_literal,
	p_nls_date_format     varchar2 default null,
	p_alignment           number   default alignment_unaligned,
	p_case_style          number   default case_lower,
	p_header              number   default header_on,
	p_header_custom_value varchar2 default null,
	p_sql_terminator      varchar2 default ';',
	p_plsql_terminator    varchar2 default chr(10)||'/',
	p_insert_style        number default insert_style_union_all,
	p_batch_size          number default 100,
	p_commit_style        number default commit_style_at_end
) return clob is
	v_cursor number;
	v_column_count number;
	--TODO: Use conditional compilation to support older versions?
	v_column_metadata  dbms_sql.desc_tab4;

	v_column_expression clob;
	v_output clob;
	v_undefined integer;

	--Store the results in a 2D array.
	v_header_columns columns_nt := columns_nt();
	v_rows rows_nt := rows_nt();
begin
	--Verify parameters and set some globals.
	verify_parameters(p_date_style, p_nls_date_format, p_alignment, p_case_style,
		p_header, p_header_custom_value, p_insert_style, p_batch_size, p_commit_style);
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

	--Start dynamic execution, retrieve data and format it.
	define_variables(v_column_count, v_column_metadata, v_cursor);
	v_undefined := dbms_sql.execute(v_cursor);
	v_rows := get_rows_from_sql(v_column_count, v_cursor, v_column_metadata, p_date_style, p_nls_date_format);
	align_values(p_alignment, v_column_count, v_rows);
	v_column_expression := get_column_expression(v_header_columns);
	v_output := get_clob_from_arrays(p_table_name, v_column_expression, v_column_count, v_rows, p_sql_terminator, p_plsql_terminator, p_insert_style, p_batch_size, p_commit_style);

	--Add header and footer.
	add_header(v_output, p_table_name, v_rows.count, p_date_style, p_nls_date_format, p_header, p_header_custom_value);
	--TODO:
	--add_footer(v_output);

	dbms_sql.close_cursor(v_cursor);
	--dbms_output.put_line(v_output);

	return v_output;
end;
end;
/
