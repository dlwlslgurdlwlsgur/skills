FROM python:3.10-slim
WORKDIR /app
ENV TZ=Asia/Seoul
RUN apt-get update && apt-get install -y tzdata && \
    ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone && \
    apt-get clean && rm -rf /var/lib/apt/lists/*
RUN pip install --no-cache-dir Flask==3.0.3 PyMySQL==1.1.1 boto3==1.34.144
COPY ./stress.py .
EXPOSE 8080
CMD ["sh", "-c", "python stress.py"]