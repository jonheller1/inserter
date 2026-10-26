create or replace package inserter_test authid current_user is
pragma serially_reusable;

/*
== Purpose ==

Unit tests for Inserter.


== Example ==

begin
	inserter_test.run;
end;

*/

--Run the unit tests and display the results in dbms output.
procedure run;

end;
/
create or replace package body inserter_test is
pragma serially_reusable;


--Global counters.
g_test_count number := 0;
g_passed_count number := 0;
g_failed_count number := 0;


--------------------------------------------------------------------------------
--Check if values are equal, update global counter, and output failures.
procedure assert_equals(p_test nvarchar2, p_expected nvarchar2, p_actual nvarchar2) is
begin
	g_test_count := g_test_count + 1;

	if p_expected = p_actual or p_expected is null and p_actual is null then
		g_passed_count := g_passed_count + 1;
	else
		g_failed_count := g_failed_count + 1;
		dbms_output.put_line('Failure with: '||p_test);
		dbms_output.put_line('Expected: '||chr(10)||'"'||p_expected||'"');
		dbms_output.put_line('Actual  : '||chr(10)||'"'||p_actual||'"');
	end if;
end assert_equals;


--------------------------------------------------------------------------------
--Check if values are equal, update global counter, and output failures.
procedure assert_like(p_test nvarchar2, p_expected nvarchar2, p_actual nvarchar2) is
begin
	g_test_count := g_test_count + 1;

	if p_actual like p_expected or p_expected is null and p_actual is null then
		g_passed_count := g_passed_count + 1;
	else
		g_failed_count := g_failed_count + 1;
		dbms_output.put_line('Failure with: '||p_test);
		dbms_output.put_line('Expected: '||chr(10)||'"'||p_expected||'"');
		dbms_output.put_line('Actual  : '||chr(10)||'"'||p_actual||'"');
	end if;
end assert_like;


--------------------------------------------------------------------------------
-- Trim expected results that are displayed in this package code with an extra
-- newline at the beginning, two tabs on each line, and a newline with two
-- extra tabs at the end.
function trim_expected_results(p_input clob) return clob is
	v_trimmed_output clob := p_input;
begin
	--Remove two tabs per line.
	v_trimmed_output := replace(v_trimmed_output, chr(10)||chr(9)||chr(9), chr(10));
	--Remove first, extra newline.
	v_trimmed_output := substr(v_trimmed_output, 2);
	--Remove last tab.
	v_trimmed_output := substr(v_trimmed_output, 1, length(v_trimmed_output)-1);

	return v_trimmed_output;
end trim_expected_results;


--------------------------------------------------------------------------------
procedure tear_down is
	v_table_does_not_exist exception;
	pragma exception_init(v_table_does_not_exist, -00942);
begin
	execute immediate 'drop table inserter_test_table_source purge';
	execute immediate 'drop table inserter_test_table_target purge';
	execute immediate 'drop table inserter_test_long';
exception when v_table_does_not_exist then null;
end tear_down;

--------------------------------------------------------------------------------
procedure setup is
begin
	execute immediate
	'
		create table inserter_test_table_source
		(
			a_number number,
			a_varchar2 varchar2(4000),
			a_date date,
			a_timestamp timestamp,
			a_rowid rowid,
			a_char char(10),
			a_nvarchar2 nvarchar2(2000)
		)
	';

	execute immediate
	q'[
		insert into inserter_test_table_source
		select 1, 'asdf', date '2000-01-01', timestamp '2000-01-01 00:00:01', null, 'asdf', n'asdf'               from dual union all
		-- unistr('\D83D\DE00') is the "Grinning Face" emoji.
		select 2, 'qwer', date '3000-01-01', timestamp '3000-01-01 00:00:01', null, 'qwer', unistr('\D83D\DE00')  from dual
	]';

	execute immediate
	q'[
		update inserter_test_table_source set a_rowid = (select min(rowid) from inserter_test_table_source)
	]';

	execute immediate
	'
		create table inserter_test_table_target as
		select * from inserter_test_table_source where 1=0
	';

	execute immediate
	'
		create table inserter_test_long
		(
			id     number,
			a_long long
		)
	';

end setup;


--------------------------------------------------------------------------------
procedure test_simple is
	v_test_name varchar2(100);
	v_actual    clob;
	v_expected  clob;
	v_options   inserter.options_rec;
begin
	-- Set common options for simple tests. These will make the output as simple as possible.
	v_options.p_target_table   := 'test1';
	v_options.p_header_style   := inserter.header_style_off;
	v_options.p_footer_style   := inserter.footer_style_off;
	v_options.p_commit_style   := inserter.commit_style_none;
	v_options.p_sql_terminator := null;
	v_options.p_column_list    := inserter.column_list_none;

	-- Run simple tests.
	v_test_name := 'Simple Test 1 - String';
	v_options.p_source_select := q'[select 'asdf' a from dual]';
	select inserter.get_script(v_options) into v_actual from dual;
	v_expected :=
	q'[
		insert into test1
		select 'asdf' from dual
	]';
	assert_equals(v_test_name, trim_expected_results(v_expected), v_actual);

	v_test_name := 'Simple Test 2 - Number';
	v_options.p_source_select := q'[select 1.00001 a from dual]';
	select inserter.get_script(v_options) into v_actual from dual;
	v_expected :=
	q'[
		insert into test1
		select 1.00001 from dual
	]';
	assert_equals(v_test_name, trim_expected_results(v_expected), v_actual);

	v_test_name := 'Simple Test 3 - Date';
	v_options.p_source_select := q'[select date '2345-06-07' a from dual]';
	select inserter.get_script(v_options) into v_actual from dual;
	v_expected :=
	q'[
		insert into test1
		select date '2345-06-07' from dual
	]';
	assert_equals(v_test_name, trim_expected_results(v_expected), v_actual);

	v_test_name := 'Simple Test 4 - SYSDATE';
	v_options.p_source_select := q'[select sysdate a from dual]';
	select inserter.get_script(v_options) into v_actual from dual;
	v_expected :=
	q'[
		insert into test1
		select timestamp '____-__-__ __:__:__' from dual
	]';
	assert_like(v_test_name, trim_expected_results(v_expected), v_actual);

	v_test_name := 'Simple Test 5 - Timestamp';
	v_options.p_source_select := q'[select timestamp '2345-06-07 01:23:45.123456789' a from dual]';
	select inserter.get_script(v_options) into v_actual from dual;
	v_expected :=
	q'[
		insert into test1
		select timestamp '2345-06-07 01:23:45.123456789' from dual
	]';
	assert_equals(v_test_name, trim_expected_results(v_expected), v_actual);

	v_test_name := 'Simple Test 6 - SYSTIMESTAMP';
	v_options.p_source_select := q'[select systimestamp a from dual]';
	select inserter.get_script(v_options) into v_actual from dual;
	v_expected :=
	q'[
		insert into test1
		select timestamp '____-__-__ __:__:__._________' from dual
	]';
	assert_like(v_test_name, trim_expected_results(v_expected), v_actual);

	v_test_name := 'Simple Test 7 - CHAR';
	v_options.p_source_select := q'[select cast('asdf' as char(10)) from dual]';
	select inserter.get_script(v_options) into v_actual from dual;
	v_expected :=
	q'[
		insert into test1
		select 'asdf      ' from dual
	]';
	assert_equals(v_test_name, trim_expected_results(v_expected), v_actual);

	v_test_name := 'Simple Test 8 - ROWID';
	v_options.p_source_select := q'[select rowid from dual]';
	select inserter.get_script(v_options) into v_actual from dual;
	v_expected :=
	q'[
		insert into test1
		select chartorowid('__________________') from dual
	]';
	assert_like(v_test_name, trim_expected_results(v_expected), v_actual);
end test_simple;


--------------------------------------------------------------------------------
procedure test_insert_style is
	v_test_name varchar2(100);
	v_actual    clob;
	v_expected  clob;
	v_options   inserter.options_rec;
begin
	-- Set common options for simple tests. These will make the output as simple as possible.
	v_options.p_target_table   := 'test1';
	v_options.p_header_style   := inserter.header_style_off;
	v_options.p_footer_style   := inserter.footer_style_off;

	-- INSERT_STYLE_SELECT_ONLY
	v_test_name := 'Insert style 1 - INSERT_STYLE_SELECT_ONLY';
	v_options.p_source_select := q'[select 'asdf' a from dual union all select 'qwer' from dual]';
	v_options.p_insert_style := inserter.insert_style_select_only;
	select inserter.get_script(v_options) into v_actual from dual;
	v_expected :=
	q'[
		select 'asdf' from dual union all
		select 'qwer' from dual;
	]';
	assert_equals(v_test_name, trim_expected_results(v_expected), v_actual);

	-- INSERT_STYLE_VALUES_CLAUSE
	v_test_name := 'Insert style 2 - INSERT_STYLE_VALUES_CLAUSE';
	v_options.p_source_select := q'[select 1 a, 'asdf' b from dual union all select 2 a, 'qwer' b from dual]';
	v_options.p_insert_style := inserter.insert_style_values_clause;
	select inserter.get_script(v_options) into v_actual from dual;
	v_expected :=
	q'[
		insert into test1(a,b) values
		(1,'asdf'),
		(2,'qwer');
	]';
	assert_equals(v_test_name, trim_expected_results(v_expected), v_actual);

end test_insert_style;


--------------------------------------------------------------------------------
procedure test_date_style is
begin
	null;

/*
function DATE_STYLE_ANSI_LITERAL        return number;
function DATE_STYLE_TO_DATE             return number;
function DATE_STYLE_ALTER_SESSION       return number;
*/

end test_date_style;


--------------------------------------------------------------------------------
procedure test_table_minus is
	v_insert_sql clob;
	v_source_count number;
	v_target_count number;
	v_rowcount number;
begin
	-- Get an executable insert statement.
	select inserter.get_script(
		p_source_select  => 'select * from inserter_test_table_source',
		p_target_table   => 'inserter_test_table_target',
		p_header_style   => inserter.header_style_off,
		p_footer_style   => inserter.footer_style_off,
		p_commit_style   => inserter.commit_style_none,
		p_sql_terminator => null)
	into v_insert_sql
	from dual;

	-- Execute it.
	execute immediate v_insert_sql;

	-- Check that the source and target rowcounts are identical.
	execute immediate 'select count(*) from inserter_test_table_source'
	into v_source_count;

	execute immediate 'select count(*) from inserter_test_table_target'
	into v_target_count;

	assert_equals('Table minus 1 - row counts', v_source_count, v_target_count);

	-- Check that the table contents are equal.
	execute immediate 'select count(*) from (select * from inserter_test_table_source minus select * from inserter_test_table_source)'
	into v_rowcount;
	assert_equals('Table minus 2 - rows different', 0, v_rowcount);

end test_table_minus;


--------------------------------------------------------------------------------
procedure test_long is
	v_test_name varchar2(100);
	v_actual    clob;
	v_expected  clob;
	v_options   inserter.options_rec;
begin
	-- Set common options for simple tests. These will make the output as simple as possible.
	v_options.p_target_table   := 'inserter_test_long';
	v_options.p_header_style   := inserter.header_style_off;
	v_options.p_footer_style   := inserter.footer_style_off;
	v_options.p_commit_style   := inserter.commit_style_none;
	v_options.p_sql_terminator := null;
	v_options.p_column_list    := inserter.column_list_none;

	-- Test a few bytes of LONG.
	v_test_name := 'LONG 1 - Small value';
	execute immediate q'[ insert into inserter_test_long values(1, 'asdf') ]';
	v_options.p_source_select := q'[select * from inserter_test_long]';
	select inserter.get_script(v_options) into v_actual from dual;
	v_expected :=
	q'[
		insert into inserter_test_long
		select 1,'asdf' from dual
	]';
	assert_equals(v_test_name, trim_expected_results(v_expected), v_actual);

	-- Test the largest possible value (for this program anyway).
	v_test_name := 'LONG 2 - Large value';
	execute immediate
	q'[
		declare
			v_long1 long := lpad('A', 4000, 'A');
		begin
			insert into inserter_test_long values(2, v_long1);
		end;
	]';
	v_options.p_source_select := q'[select * from inserter_test_long where id = 2]';
	select inserter.get_script(v_options) into v_actual from dual;
	v_expected := replace(
	q'[
		insert into inserter_test_long
		select 2,'#4KA#' from dual
	]', '#4KA#', lpad('A', 4000, 'A'));
	assert_equals(v_test_name, trim_expected_results(v_expected), v_actual);

	-- Test a value that is too large to meaningfully export.
	v_test_name := 'LONG 3 - Large value';
	execute immediate
	q'[
		declare
			-- Note that you cannot simply concatenate varchar2s to make the long.
			v_long1 long := lpad('A', 4000, 'A');
			v_long2 long := 'A';
			v_long3 long := v_long1 || v_long2;
		begin
			insert into inserter_test_long values(3, v_long3);
		end;
	]';
	v_options.p_source_select := q'[select * from inserter_test_long where id = 3]';
	begin
		select inserter.get_script(v_options) into v_actual from dual;
		assert_equals(v_test_name, 'An exception', 'No exception');
	exception when others then
		assert_like(v_test_name, 'ORA-20000: Error exporting row 1 for column A_LONG. '||
			'Inserter Cannot export a LONG larger than 4000 bytes. '||
			'For large data, you may want to consider another tool, such as Oracle Data Pump.%',
			sqlerrm);
	end;

end test_long;


--------------------------------------------------------------------------------
procedure test_unsupported_types is
	v_unused_result clob;
	v_error_message clob;
	v_expected  clob;
begin
	-- Error message for only one unsupported column.
	begin
		select inserter.get_script(p_source_select => q'[select hextoraw('54657374') a from dual]')
		into v_unused_result
		from dual;
	exception when others then
		v_error_message := sqlerrm;
	end;
	v_expected :=
	q'[
		ORA-20000: This column has an unexpected or unsupported type. Either remove this column or rewrite it into an expression that returns a supported type, such as VARCHAR2.
		Name: A, Type: RAW, Type Code: 23
	]';
	assert_like('Unupported type 1 - One bad columns', trim_expected_results(v_expected) || '%', v_error_message);

	-- Error message for multiple unsupported columns.
	begin
		select inserter.get_script(p_source_select => q'[select hextoraw('54657374') a, hextoraw('54657374') b from dual]')
		into v_unused_result
		from dual;
	exception when others then
		v_error_message := sqlerrm;
	end;
	v_expected :=
	q'[
		ORA-20000: These columns have unexpected or unsupported types. Either remove these columns or rewrite them into expressions that return a supported type, such as VARCHAR2.
		Name: A, Type: RAW, Type Code: 23
		Name: B, Type: RAW, Type Code: 23
	]';
	assert_like('Unupported type 2 - Two bad columns', trim_expected_results(v_expected) || '%', v_error_message);

end test_unsupported_types;


--------------------------------------------------------------------------------
procedure run is
begin
	--Reset counters.
	g_test_count := 0;
	g_passed_count := 0;
	g_failed_count := 0;

	--Print header.
	dbms_output.put_line(null);
	dbms_output.put_line('----------------------------------------');
	dbms_output.put_line('Inserter Test Summary');
	dbms_output.put_line('----------------------------------------');

	--Prepare for the tests.
	tear_down;
	setup;

	--Run the tests.
	test_simple;
	test_insert_style;
	test_date_style;
	test_table_minus;
	test_long;
	test_unsupported_types;

	--Clean up the tests.
	--TODO: It's convenient to have the test tables exist afterwards.
	--tear_down;

	--Print summary of results.
	dbms_output.put_line(null);
	dbms_output.put_line('Total : '||g_test_count);
	dbms_output.put_line('Passed: '||g_passed_count);
	dbms_output.put_line('Failed: '||g_failed_count);

	--Print easy to read pass or fail message.
	if g_failed_count = 0 then
		dbms_output.put_line('
  _____         _____ _____
 |  __ \ /\    / ____/ ____|
 | |__) /  \  | (___| (___
 |  ___/ /\ \  \___ \\___ \
 | |  / ____ \ ____) |___) |
 |_| /_/    \_\_____/_____/');
	else
		dbms_output.put_line('
  ______      _____ _
 |  ____/\   |_   _| |
 | |__ /  \    | | | |
 |  __/ /\ \   | | | |
 | | / ____ \ _| |_| |____
 |_|/_/    \_\_____|______|');
	end if;
end run;

end inserter_test;
/
