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
	execute immediate 'drop table inserter_test_table purge';
exception when v_table_does_not_exist then null;
end tear_down;

--------------------------------------------------------------------------------
procedure setup is
begin
	execute immediate
	'
		create table inserter_test_table
		(
			a_number number,
			a_varchar2 varchar2(4000),
			a_date date,
			a_timestamp timestamp
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

	--Clean up the tests.
	tear_down;

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
