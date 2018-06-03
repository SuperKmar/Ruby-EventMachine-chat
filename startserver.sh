#!bin/bash
ruby -w Server.rb  2>&1 | tee serverlog.txt &
middleman &
exit 0
