FROM node:14-alpine3.17 as node
FROM ruby:3.0-alpine3.15 as base
ENV BUNDLE_BUILD__SASSC=--disable-march-tune-native
ENV BUNDLE_WITHOUT=test:development
ENV ROOT=/loomio

COPY --from=node /usr/lib /usr/lib
COPY --from=node /usr/local/share /usr/local/share
COPY --from=node /usr/local/lib /usr/local/lib
COPY --from=node /usr/local/include /usr/local/include
COPY --from=node /usr/local/bin /usr/local/bin
RUN gem update --system \
  && apk update \
  && apk upgrade \
  # Install dependencies:
  && apk --update --no-cache add \
      # help with native gem compilation
      build-base ruby-dev alpine-sdk python3 \
      icu-dev cmake libc-dev linux-headers libxml2-dev libxslt-dev readline-dev gcc \
      # timezone management
      tzdata \
      # postgres connection
      postgresql-dev postgresql-client \
      # deps for gem charlock_holmes and nokogiri, to use system libraries
      ruby-charlock_holmes \
      ruby-nokogiri \
      # image processing
      imagemagick \
      # gem using git
      git \
  && rm -rf /var/cache/apk/*


WORKDIR $ROOT
ADD Gemfile Gemfile.lock $ROOT
RUN bundle config set --global without 'development:test' \
  && bundle config set --global path 'vendor' \
  && bundle install \
  && mkdir -p $ROOT/tmp/pids $ROOT/tmp/sockets

ADD . $ROOT
ENV NODE_OPTIONS=--openssl-legacy-provider
WORKDIR $ROOT/vue
RUN npm ci \
  && npm run build
RUN SECRET_KEY_BASE="assets" bundle exec rails assets:precompile \
  && rm -rf node_modules tmp/* .npm .gem spec test
WORKDIR /loomio

FROM ruby:3.0-alpine3.15
ENV BUNDLE_BUILD__SASSC=--disable-march-tune-native
ENV BUNDLE_WITHOUT=test:development
ENV ROOT=/loomio

RUN gem update --system \
  && apk update \
  && apk upgrade \
  && gem install bundler --silent \
  # Install dependencies:
  && apk --update --no-cache add \
    # nokogiri native deps (don't need full ruby-nokogiri, just these headers)
    libxslt-dev \
    # manage timezones
    tzdata \
    # communicate with postgres through the postgres gem
    postgresql-dev \
    # for image processing
    imagemagick \
    # allows gem to use git
    git \
    # seven_zip gem dep
    p7zip \ 
  && rm -rf /var/cache/apk/* \
  # Prepare workspace users
  && addgroup -S loomio \
  && adduser -S loomio -G loomio \
  # Link logs to common alpine log directory
  && mkdir -p $ROOT/log \
  && truncate -s 0 /var/log/*log \
  && chown loomio:loomio /etc/motd

USER loomio
COPY --from=base --chown=loomio:loomio $ROOT $ROOT
WORKDIR $ROOT
RUN bundle config set --global without 'development:test' \
  && bundle config set --global path 'vendor' \
  && mkdir -p $ROOT/tmp/pids $ROOT/tmp/sockets

EXPOSE 3000

# source the config file and run puma when the container starts
CMD /loomio/docker_start.sh

