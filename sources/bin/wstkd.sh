#!/bin/bash
APP_HOME='/opt/pdns'
PERL5LIB="$APP_HOME/libs" $APP_HOME/bin/wstkd.pl -h $APP_HOME -a $1

