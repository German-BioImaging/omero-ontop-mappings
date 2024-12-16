create user ontop with password '!ontop$';
grant select on all tables in schema public to ontop;
alter default privileges in schema public grant select on tables to ontop;
