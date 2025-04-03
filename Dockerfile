FROM python:3.11-slim

WORKDIR /app

# Copy requirements and install dependencies
COPY src/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application code
COPY src/ .

# Expose port
EXPOSE 8000

# Command to run application
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]
