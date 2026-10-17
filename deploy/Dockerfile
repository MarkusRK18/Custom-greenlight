FROM ruby:3.2-bookworm
WORKDIR /usr/src/app
RUN apt-get update && apt-get install -y --no-install-recommends build-essential libpq-dev libyaml-dev imagemagick nodejs npm && rm -rf /var/lib/apt/lists/*
ENV RAILS_ENV=production RAILS_LOG_TO_STDOUT=true RAILS_SERVE_STATIC_FILES=true BUNDLE_WITHOUT=development:test
COPY Gemfile Gemfile.lock ./
RUN bundle install --jobs 4
COPY package.json package-lock.json ./
RUN npm install --global yarn@1.22.22 && npm ci --no-audit --no-fund
COPY . .
ARG RELATIVE_URL_ROOT=""
ENV RELATIVE_URL_ROOT=${RELATIVE_URL_ROOT}
RUN SKIP_YARN_INSTALL=1 SECRET_KEY_BASE=build-placeholder bundle exec rails assets:precompile
EXPOSE 3000
CMD ["bundle", "exec", "rails", "server", "-b", "0.0.0.0", "-p", "3000"]
