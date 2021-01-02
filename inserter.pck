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

function HEADER_STYLE_ON                return number;
function HEADER_STYLE_OFF               return number;
function HEADER_STYLE_CUSTOM            return number;

function FOOTER_STYLE_ON                return number;
function FOOTER_STYLE_OFF               return number;
function FOOTER_STYLE_CUSTOM            return number;

function INSERT_STYLE_UNION_ALL         return number;
function INSERT_STYLE_INSERT_ALL        return number;
function INSERT_STYLE_VALUES            return number;
function INSERT_STYLE_VALUES_PLSQLBLOCK return number;

function BATCH_SIZE_ALL                 return number;

function COMMIT_STYLE_AT_END            return number;
function COMMIT_STYLE_NONE              return number;
function COMMIT_STYLE_PER_BATCH         return number;

function ESCAPE_STYLE_TWO_QUOTES        return number;
function ESCAPE_STYLE_Q_QUOTES          return number;

--Main function
function get_script
(
	p_table_name          varchar2,
	p_select              clob,
	p_date_style          number   default date_style_ansi_literal,
	p_nls_date_format     varchar2 default null,
	p_alignment           number   default alignment_unaligned,
	p_case_style          number   default case_lower,
	p_header_style        number   default header_style_on,
	p_header_custom_value varchar2 default null,
	p_footer_style        number   default footer_style_on,
	p_footer_custom_value varchar2 default null,
	p_sql_terminator      varchar2 default ';',
	p_plsql_terminator    varchar2 default chr(10)||'/',
	p_insert_style        number default insert_style_union_all,
	p_batch_size          number default 100,
	p_commit_style        number default commit_style_at_end,
	p_escape_style        number default escape_style_two_quotes
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
g_begin               varchar2(100) := 'begin';
g_end                 varchar2(100) := 'end';
--TODO: Parameterize this?
g_indent              varchar2(100) := '  ';

--Almost all possible ASCII delimiters, except a few ones that would cause problems,
-- like comma, double quote, ampersand, and at sign.
--(These are global constants to avoid being executed with each function call.)
c_start_delimiters constant sys.odcivarchar2list := sys.odcivarchar2list(
	'[','{','<','(',
	'!','#','$','%','*','+',',','-','.','0','1','2','3','4','5','6','7','8','9',
	':',';','=','?','A','B','C','D','E','F','G','H','I','J','K','L','M','N','O',
	'P','Q','R','S','T','U','V','W','X','Y','Z','^','_','`','a','b','c','d','e',
	'f','g','h','i','j','k','l','m','n','o','p','q','r','s','t','u','v','w','x',
	'y','z','|','~'
);
c_end_delimiters constant sys.odcivarchar2list := sys.odcivarchar2list(
	']','}','>',')',
	'!','#','$','%','*','+',',','-','.','0','1','2','3','4','5','6','7','8','9',
	':',';','=','?','A','B','C','D','E','F','G','H','I','J','K','L','M','N','O',
	'P','Q','R','S','T','U','V','W','X','Y','Z','^','_','`','a','b','c','d','e',
	'f','g','h','i','j','k','l','m','n','o','p','q','r','s','t','u','v','w','x',
	'y','z','|','~'
);

--Functions that act like constants.
function DATE_STYLE_ANSI_LITERAL        return number is begin return 1; end;
function DATE_STYLE_TO_DATE             return number is begin return 2; end;
function DATE_STYLE_ALTER_SESSION       return number is begin return 3; end;

function ALIGNMENT_UNALIGNED            return number is begin return 5; end;
function ALIGNMENT_ALIGNED              return number is begin return 4; end;

function CASE_LOWER                     return number is begin return 7; end;
function CASE_UPPER                     return number is begin return 6; end;
function CASE_CAMEL                     return number is begin return 8; end;

function HEADER_STYLE_ON                return number is begin return 9; end;
function HEADER_STYLE_OFF               return number is begin return 10; end;
function HEADER_STYLE_CUSTOM            return number is begin return 11; end;

function FOOTER_STYLE_ON                return number is begin return 12; end;
function FOOTER_STYLE_OFF               return number is begin return 13; end;
function FOOTER_STYLE_CUSTOM            return number is begin return 14; end;

function INSERT_STYLE_UNION_ALL         return number is begin return 15; end;
function INSERT_STYLE_INSERT_ALL        return number is begin return 16; end;
function INSERT_STYLE_VALUES            return number is begin return 17; end;
function INSERT_STYLE_VALUES_PLSQLBLOCK return number is begin return 18; end;

function BATCH_SIZE_ALL                 return number is begin return 19; end;

function COMMIT_STYLE_AT_END            return number is begin return 20; end;
function COMMIT_STYLE_NONE              return number is begin return 21; end;
function COMMIT_STYLE_PER_BATCH         return number is begin return 22; end;

function ESCAPE_STYLE_TWO_QUOTES        return number is begin return 23; end;
function ESCAPE_STYLE_Q_QUOTES          return number is begin return 24; end;

--------------------------------------------------------------------------------------------------------------------------
procedure verify_parameters(p_date_style number, p_nls_date_format varchar2, p_alignment number, p_case_style number,
	p_header_style number, p_header_custom_value varchar2, p_footer_style varchar2, p_footer_custom_value varchar2,
	p_insert_style number, p_batch_size number, p_commit_style number, p_escape_style number
) is
	v_throwaway varchar2(32767);
begin
	--Check that P_DATE_STYLE is correct.
	if p_date_style in (inserter.date_style_ansi_literal, inserter.date_style_to_date, inserter.date_style_alter_session) then
		null;
	else
		raise_application_error(-20000, 'p_date_style must be one of DATE_STYLE_ANSI_LITERAL, DATE_STYLE_TO_DATE, or DATE_STYLE_ALTER_SESSION.');
	end if;

	--Check that P_DATE_STYLE and P_NLS_DATE_FORMAT are set correctly together.
	if p_date_style = inserter.date_style_ansi_literal and p_nls_date_format is not null then
		raise_application_error(-20000, 'If P_DATE_STYLE is set to DATE_STYLE_ANSI_LITERAL then P_NLS_DATE_FORMAT should be null.');
	end if;

	--Check that P_DATE_STYLE and P_NLS_DATE_FORMAT are set correctly together.
	if p_date_style in (inserter.date_style_to_date, inserter.date_style_alter_session) and p_nls_date_format is null then
		raise_application_error(-20000, 'If P_DATE_STYLE is set to DATE_STYLE_TO_DATE or DATE_STYLE_ALTER_SESSION, then P_NLS_DATE_FORMAT cannot be null.');
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
		raise_application_error(-20000, 'P_ALIGNMENT must be set to either ALIGNMENT_UNALIGNED or ALIGNMENT_ALIGNED.');
	end if;

	--Check P_CASE_STYLE.
	if p_case_style in (case_upper, case_lower, case_camel) then
		null;
	else
		raise_application_error(-20000, 'P_CASE_STYLE must be set to either CASE_STYLE_LOWER, CASE_STYLE_UPPER, or CASE_STYLE_CAMEL.');
	end if;

	--Check P_HEADER.
	if p_header_style in (header_style_on, header_style_off, header_style_custom) then
		null;
	else
		raise_application_error(-20000, 'P_HEADER_STYLE must be set to either HEADER_STYLE_ON, HEADER_STYLE_OFF, or HEADER_STYLE_CUSTOM.');
	end if;

	if p_header_style in (header_style_on, header_style_off) and p_header_custom_value is not null then
		raise_application_error(-20000, 'P_HEADER_CUSTOM_VALUE is only useful if P_HEADER_STYLE is set to HEADER_STYLE_CUSTOM.');
	end if;

	if p_header_style = header_style_custom and p_header_custom_value is null then
		raise_application_error(-20000, 'If P_HEADER_STYLE is set to HEADER_STYLE_CUSTOM, then P_HEADER_CUSTOM_VALUE should be non-null.');
	end if;

	--Check P_FOOTER.
	if p_footer_style in (footer_style_on, footer_style_off, footer_style_custom) then
		null;
	else
		raise_application_error(-20000, 'P_FOOTER_STYLE must be set to either FOOTER_STYLE_ON, FOOTER_STYLE_OFF, or FOOTER_STYLE_CUSTOM.');
	end if;

	if p_footer_style in (footer_style_on, footer_style_off) and p_footer_custom_value is not null then
		raise_application_error(-20000, 'P_FOOTER_CUSTOM_VALUE is only useful if P_FOOTER_STYLE is set to FOOTER_STYLE_CUSTOM.');
	end if;

	if p_footer_style = footer_style_custom and p_footer_custom_value is null then
		raise_application_error(-20000, 'If P_FOOTER_STYLE is set to FOOTER_STYLE_CUSTOM, then P_FOOTER_CUSTOM_VALUE should be non-null.');
	end if;

	--TODO:
	--p_insert_style, p_batch_size, p_commit_style

	if p_escape_style in (ESCAPE_STYLE_TWO_QUOTES, ESCAPE_STYLE_Q_QUOTES) then
		null;
	else
		raise_application_error(-20000, 'P_ESCAPE_STYLE must be set to either ESCAPE_STYLE_TWO_QUOTES or ESCAPE_STYLE_Q_QUOTES.');
	end if;

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
		g_begin       := upper(g_begin);
		g_end         := upper(g_end);
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
		g_begin       := initcap(g_begin);
		g_end         := initcap(g_end);
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
procedure replace_header_footer_vars(
	p_text in out nocopy clob,
	p_table_name varchar2,
	p_rowcount number
) is
	v_row_or_rows varchar2(100);
begin
	--Set singular or plural depending on the count.
	if p_rowcount = 1 then
		v_row_or_rows := 'row';
	else
		v_row_or_rows := 'rows';
	end if;

	--Replace variables, if any.
	p_text := replace(replace(replace(replace(replace(p_text
		,'#ROWCOUNT#', p_rowcount)
		,'#ROW_OR_ROWS#', v_row_or_rows)
		,'#USER#', user)
		,'#DATE#', to_char(sysdate, 'YYYY-MM-DD HH24:MI:SS'))
		,'#TABLE#', p_table_name);

end replace_header_footer_vars;


--------------------------------------------------------------------------------
procedure add_header
(
	p_output in out nocopy clob,
	p_table_name varchar2,
	p_rowcount number,
	p_date_style number,
	p_nls_date_format varchar2,
	p_header_style varchar2,
	p_header_custom_value varchar2
) is
	v_header clob;
	v_row_or_rows varchar2(100);
	v_template varchar2(32767) := substr(replace(
		q'[
		------------------------------------------------------------------------
		-- Begin inserting #ROWCOUNT# #ROW_OR_ROWS# into #TABLE#.
		-- This script was generated by #USER# on #DATE#.
		------------------------------------------------------------------------
		]'
		,chr(10)||'		', chr(10))
		,2);
begin
	dbms_lob.createtemporary(v_header, true);

	--Choose which header style to start with.
	if p_header_style = header_style_on then
		v_header := v_template;
	elsif p_header_style = header_style_off then
		null;
	elsif p_header_style = header_style_custom then
		v_header := p_header_custom_value;
	end if;

	--Replace variables, if any.
	replace_header_footer_vars(v_header, p_table_name, p_rowcount);

	--Alter the session, if requested.
	if p_date_style = inserter.date_style_alter_session then
		v_header := v_header || 'alter session set nls_date_format = '''||p_nls_date_format||''';' || chr(10);
	end if;

	--TODO: There's gotta be a better way to do this.
	dbms_lob.append(v_header, p_output);
	p_output := v_header;
end add_header;

--------------------------------------------------------------------------------
procedure add_footer
(
	p_output in out nocopy clob,
	p_table_name varchar2,
	p_rowcount number,
	p_footer_style varchar2,
	p_footer_custom_value varchar2
) is
	v_footer clob;
	v_row_or_rows varchar2(100);
	v_template varchar2(32767) := substr(replace(
		q'[
		------------------------------------------------------------------------
		-- End inserting #ROWCOUNT# #ROW_OR_ROWS# into #TABLE#.
		------------------------------------------------------------------------
		]'
		,chr(10)||'		', chr(10))
		,2);
begin
	dbms_lob.createtemporary(v_footer, true);

	--Choose which footer style to start with.
	if p_footer_style = footer_style_on then
		v_footer := v_template;
	elsif p_footer_style = footer_style_off then
		null;
	elsif p_footer_style = footer_style_custom then
		v_footer := p_footer_custom_value;
	end if;

	--Replace variables, if any.
	replace_header_footer_vars(v_footer, p_table_name, p_rowcount);

	--Add the footer.
	if v_footer is not null then
		dbms_lob.append(p_output, v_footer);
	end if;
end add_footer;

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
function get_string_from_varchar2(p_varchar2 varchar2, p_escape_style number) return varchar2 is
	v_escape_start varchar2(1);
	v_escape_end   varchar2(1);

	---------------------------------------------------------------------------
	--Return available quote delimiters so there's no conflict with the user's code.
	procedure get_available_quote_delimiter(p_string in varchar2, p_start_delimiter out varchar2, p_end_delimiter out varchar2) is
	begin
		--Find the first available delimiter and return it.
		for i in 1 .. c_end_delimiters.count loop
			if instr(p_string, c_end_delimiters(i)||'''') = 0 then
				p_start_delimiter := c_start_delimiters(i);
				p_end_delimiter   := c_end_delimiters(i);
				return;
			end if;
		end loop;

		--Exhausting all identifiers is possible, but incredibly unlikely.
		raise_application_error(-20010, 'You have used every possible quote identifier, '||
			'you must remove at least one from the code.');
	end get_available_quote_delimiter;
begin
	if p_varchar2 is null then
		return g_null;
	else
		--For escaping, just double up the quotes.
		if p_escape_style = escape_style_two_quotes then
			return '''' || replace(p_varchar2, '''', '''''') || '''';
		--For q quotes, find an available escape, and add it to the front and back if necessary.
		else
			if instr(p_varchar2, '''') <> 0 then
				get_available_quote_delimiter(p_varchar2, v_escape_start, v_escape_end);
				return 'q''' || v_escape_start || p_varchar2 || v_escape_end || '''';
			else
				return '''' || p_varchar2 || '''';
			end if;
		end if;
	end if;
end get_string_from_varchar2;

--------------------------------------------------------------------------------
function get_string_from_nvarchar2(p_nvarchar2 varchar2, p_escape_style number) return varchar2 is
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
	p_nls_date_format varchar2,
	p_escape_style number
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
				v_columns(i) := get_string_from_varchar2(v_varchar2, p_escape_style);
			elsif v_column_metadata(i).col_type in (dbms_types.typecode_nchar, dbms_types.typecode_nvarchar2) then
				dbms_sql.column_value(v_cursor, i, v_nvarchar2);
				v_columns(i) := get_string_from_nvarchar2(v_nvarchar2, p_escape_style);
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
		--End the batch.
		if i = v_rows.count or mod(i, p_batch_size) = 0 then
			if p_insert_style = insert_style_values_plsqlblock then
				--Don't use sql_terminator here - inside a PL/SQL block, nothing but ";" will work.
				v_row := v_row || chr(10) || g_end || ';' || p_plsql_terminator;

				if i = v_rows.count and p_commit_style in (commit_style_at_end, commit_style_per_batch) then
					v_row := v_row || chr(10) || 'commit' || p_sql_terminator;
				elsif p_commit_style = commit_style_per_batch then
					v_row := v_row || chr(10) || 'commit' || p_sql_terminator;
				end if;
			else
				if p_insert_style = insert_style_insert_all then
					v_row := v_row || chr(10) || 'select * from dual';
				end if;

				v_row := v_row || p_sql_terminator;

				if i = v_rows.count and p_commit_style in (commit_style_at_end, commit_style_per_batch) then
					v_row := v_row || chr(10) || 'commit' || p_sql_terminator;
				elsif p_commit_style = commit_style_per_batch then
					v_row := v_row || chr(10) || 'commit' || p_sql_terminator;
				end if;
			end if;
		--End just the row.
		else
			if p_insert_style = insert_style_union_all then
				v_row := v_row || ' ' || g_union_all;
			elsif p_insert_style = insert_style_insert_all then
				null;
			end if;
		end if;
	end end_batch;

begin
	dbms_lob.createtemporary(v_output, true);

	--TODO: What if no rows?
	--TODO: Add row count message: "Insert X rows into TABLE_NAME."

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
			v_row := v_row || ')';

			--End a batch.
			end_batch(i);
		elsif p_insert_style = insert_style_values then
			--Every row is filled out the same.
			v_row := g_insert_into || ' ' || trim(p_table_name) || p_column_expression || ' ' || g_values || '(';
			add_values(i);
			--(Don't use sql_terminator here - only ";" can ever work inside a PL/SQL block.
			v_row := v_row || ');';

			--Add commit, if necessary.
			if p_commit_style = commit_style_per_batch or
				(i = v_rows.count and p_commit_style = commit_style_at_end)
			then
				v_row := v_row || chr(10) || 'commit' || p_sql_terminator;
			end if;
		elsif p_insert_style = insert_style_values_plsqlblock then
			--Start a batch.
			if i = 1 or mod(i-1, p_batch_size) = 0 then
				v_row := g_begin || chr(10);
			end if;

			v_row := v_row || g_indent || g_insert_into || ' ' || trim(p_table_name) || p_column_expression || ' ' || g_values || '(';
			add_values(i);
			v_row := v_row || ')' || p_sql_terminator;

			--End a batch.
			end_batch(i);
		end if;

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
	p_header_style        number   default header_style_on,
	p_header_custom_value varchar2 default null,
	p_footer_style        number   default footer_style_on,
	p_footer_custom_value varchar2 default null,
	p_sql_terminator      varchar2 default ';',
	p_plsql_terminator    varchar2 default chr(10)||'/',
	p_insert_style        number default insert_style_union_all,
	p_batch_size          number default 100,
	p_commit_style        number default commit_style_at_end,
	p_escape_style        number default escape_style_two_quotes
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
		p_header_style, p_header_custom_value, p_footer_style, p_footer_custom_value,
		p_insert_style, p_batch_size, p_commit_style, p_escape_style);
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
	v_rows := get_rows_from_sql(v_column_count, v_cursor, v_column_metadata, p_date_style, p_nls_date_format, p_escape_style);
	align_values(p_alignment, v_column_count, v_rows);
	v_column_expression := get_column_expression(v_header_columns);
	v_output := get_clob_from_arrays(p_table_name, v_column_expression, v_column_count, v_rows, p_sql_terminator, p_plsql_terminator, p_insert_style, p_batch_size, p_commit_style);

	--Add header and footer.
	add_header(v_output, p_table_name, v_rows.count, p_date_style, p_nls_date_format, p_header_style, p_header_custom_value);
	add_footer(v_output, p_table_name, v_rows.count, p_footer_style, p_footer_custom_value);

	dbms_sql.close_cursor(v_cursor);
	--dbms_output.put_line(v_output);

	return v_output;
end;
end;
/
