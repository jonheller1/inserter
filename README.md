INSERTER
=========

(EXPERIMENTAL - DO NOT USE YET)

Create Oracle INSERT scripts that are fast and readable.

For most data loads, it's better to use data pump or your IDE's export tool; data pump works best for quickly loading large or complex data, and your IDE works best for creating quick and dirty INSERT scripts.

But datapump requires server access, and creates binary files not suitable for version control. Existing IDEs produce human-readable scripts, but they're ugly and painfully slow.

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

## License
`plsql_lexer` is licensed under the LGPL.
