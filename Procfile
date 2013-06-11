web: bundle exec rackup config.ru -p $PORT
resque: env TERM_CHILD=1 bundle exec rake QUEUE=pop_task resque:work