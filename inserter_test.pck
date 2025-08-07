create or replace package inserter_test authid current_user is
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
		dbms_output.put_line('Expected: '||p_expected);
		dbms_output.put_line('Actual  : '||p_actual);
	end if;
end assert_equals;


--------------------------------------------------------------------------------
-- Trim text for testing. For readability, results are displayed in a string with
-- an extra newline at the beginning, three tabs on each line, and a newline with
-- two extra tabs at the end.
function trim_test(p_input clob) return clob is
	v_trimmed_output clob := p_input;
begin
	--Remove three tabs per line.
	v_trimmed_output := replace(v_trimmed_output, chr(10)||chr(9)||chr(9)||chr(9), chr(10));
	--Remove first, extra newline.
	v_trimmed_output := substr(v_trimmed_output, 2);
	--Remove last two tabs.
	v_trimmed_output := substr(v_trimmed_output, 1, length(v_trimmed_output)-2);

	return v_trimmed_output;
end trim_test;


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
	v_results clob;
begin
	--Simplest possible test of one value.
	v_results := inserter.get_script
	(
		p_table_name => 'target_table',
		p_select => 'select 1 a from dual',
		p_header_style => inserter.header_style_off,
		p_footer_style => inserter.footer_style_off
	);

	assert_equals('Simple 1',
		trim_test(
		q'[
			insert into target_table(A)
			select 1 from dual;
			commit;
		]'), v_results);
end test_simple;


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
