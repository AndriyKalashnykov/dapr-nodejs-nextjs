import { registerOTel } from "@vercel/otel";

const serviceName = process.env.SERVICE_NAME || "web-nextjs";

if (process.env.OTEL_EXPORTER_OTLP_ENDPOINT) {
  registerOTel({ serviceName });
}
