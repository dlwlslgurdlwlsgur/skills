FROM python:3.9-slim
RUN pip install boto3
COPY worker.py /app/worker.py
WORKDIR /app
CMD ["python", "worker.py"]