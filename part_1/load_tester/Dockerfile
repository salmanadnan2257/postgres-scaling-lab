FROM ubuntu:24.04
WORKDIR /app
ARG TARGETARCH
COPY ./load_tester_${TARGETARCH} ./load_tester
RUN chmod +x ./load_tester
CMD ["./load_tester"]
