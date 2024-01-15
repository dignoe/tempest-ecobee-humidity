FROM ruby:alpine

WORKDIR /usr/src/app

COPY . .

CMD ["./set_humidity.rb"]
