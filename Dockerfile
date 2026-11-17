FROM barichello/godot-ci:4.4.1

WORKDIR /app
COPY . /app

ENV GODOT_SILENCE_ROOT_WARNING=1
EXPOSE 10000

CMD ["godot", "--headless", "--path", "godot", "--", "--server"]
