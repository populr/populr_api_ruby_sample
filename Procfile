web: bundle exec unicorn -p $PORT -E $RACK_ENV
resque: env TERM_CHILD=1 bundle exec rake QUEUE=pop_task resque:work