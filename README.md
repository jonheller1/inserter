INSERTER
========

(EXPERIMENTAL - DO NOT USE YET)

Create Oracle INSERT scripts that are fast and human readable.

For most data loads, it's better to use data pump or your IDE's export tool; data pump works best for quickly loading large or complex data, and your IDE works best for creating quick INSERT scripts.

But datapump requires server access, and creates binary files not suitable for version control. IDEs produce simple text file scripts, but they're ugly and painfully slow.

Inserter aims for the sweet spot - nicey-formatted INSERT scripts that run 10 times faster than naive implementations.

## How to Install

Click the "Download ZIP" button, extract the files, CD to the directory with those files, connect to SQL*Plus, and run these commands:

1. Create objects and packages on the desired schema:

	alter session set current_schema=&schema_name;
	@install_inserter

2. Install unit tests (optional):

	alter session set current_schema=&schema_name;
	@install_inserter_unit_tests

## How to uninstall

	alter session set current_schema=&schema_name;
	@uninstall_inserter

## Simple Example

	SQL> select inserter.get_script(p_table_name => 'target_table', p_select => 'select * from user_objects') from dual;

## Parameters

Required Parameters:

* **P_TABLE_NAME** - The name of the table inserted into.
* **P_SELECT** - A valid SELECT statement. Do not include a semicolon at the end.

Optional Parameters:

* **P_DATE_STYLE** - Either DATE_STYLE_ANSI_LITERAL (default), DATE_STYLE_TO_DATE, or DATE_STYLE_ALTER_SESSION.
* **P_NLS_DATE_FORMAT** - A valid date format string. Only valid if P_DATE_STYLE is TO_DATE or ALTER_SESSION.
* **P_ALIGNMENT** - Either ALIGNMENT_UNALIGNED (default) or ALIGNMENT_ALIGNED.
* **P_CASE_STYLE** - Either CASE_LOWER (default), CASE_UPPER, or CASE_CAMEL.
* **P_HEADER_STYLE** - Either HEADER_STYLE_ON (default), HEADER_STYLE_OFF, or HEADER_STYLE_CUSTOM.
* **P_HEADER_CUSTOM_VALUE** - If HEADER_STYLE_CUSTOM is set, replace the default header with your custom string. The value can use one of these macros: #ROWCOUNT#, #ROW_OR_ROWS#, #USER#, #DATE#, #TABLE#, #SET_DEFINE_OFF#.
* **P_FOOTER_STYLE** - Either HEADER_STYLE_ON (default), HEADER_STYLE_OFF, or HEADER_STYLE_CUSTOM.
* **P_FOOTER_CUSTOM_VALUE** - If FOOTER_STYLE_CUSTOM is set, replace the default header with your custom string. The value can use one of these macros: #ROWCOUNT#, #ROW_OR_ROWS#, #USER#, #DATE#, #TABLE#.
* **P_SQL_TERMINATOR** - Character at the end of each SQL statement - ';' by default.
* **P_PLSQL_TERMINATOR** - Character at the end of each PL/SQL block - chr(10)||'/' by default.
* **P_INSERT_STYLE** - Either:

		INSERT_STYLE_UNION_ALL (default) - Usually the cleanest, fastest way to batch inserts.
			insert into t1(c1)
			select 1 from dual union all
			select 2 from dual;
		INSERT_STYLE_INSERT_ALL - Another batching method but wordier and slower than the UNION ALL approach.
			insert all
				into t1(c1) values(1)
				into t1(c1) values(2)
			select * from dual;
		INSERT_STYLE_VALUES - The simplest, slowest approach.
			insert into t1(c1) values (1);
			insert into t1(c1) values (2);
		INSERT_STYLE_VALUES_PLSQLBLOCK - Not as fast as other batching method, but a good compromise if you want simple inserts.
			begin
				insert into t1(c1) values (1);
				insert into t1(c1) values (2);
			end;
			/
* **P_BATCH_SIZE** - The number of rows included in one batch (default 100). Different sizes run into parsing and compiling problems as the size increases and the Oracle version decreases. In general, I recommend not exceeding 1000.
* **P_COMMIT_STYLE** - Either COMMIT_STYLE_AT_END (default), COMMIT_STYLE_NONE, or COMMIT_STYLE_PER_BATCH
* **P_ESCAPE_STYLE** - Either ESCAPE_STYLE_TWO_QUOTES (default) or ESCAPE_STYLE_Q_QUOTES (q'[...]' style)
* **P_COLUMN_LIST** - Either COLUMN_LIST_DERIVED_FROM_SQL (default), COLUMN_LIST_DERIVED_FROM_TABLE, or COLUMN_LIST_NONE.


## License
`plsql_lexer` is licensed under the LGPL.
