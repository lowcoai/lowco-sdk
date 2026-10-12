import { defineNode, NodeError } from "@lowcoai/nodes";

const API = "https://api.acme-crm.example/v1";
const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

// Creates a contact, or returns the existing one for the email. The "crm"
// input is a connection picked in the designer: ctx.http adds its credentials
// outside the sandbox, so this code never sees the API key.
export const createContact = defineNode({
  key: "acme_create_contact",
  name: "Create contact",
  description: "Creates an Acme CRM contact, or returns the existing one with that email.",
  category: "Acme CRM",
  icon: "user-plus",
  inputs: [
    { name: "crm", displayName: "Acme CRM account", type: "connection", required: true },
    { name: "email", displayName: "Email", type: "string", required: true },
    { name: "name", displayName: "Name", type: "string" },
    { name: "tags", displayName: "Tags", type: "string", description: "Comma-separated" },
  ],
  outputSchema: {
    type: "object",
    properties: {
      id: { type: "string" },
      email: { type: "string" },
      created: { type: "boolean" },
    },
    required: ["id", "email", "created"],
  },

  input: (inputs) => ({
    ...inputs,
    email: String(inputs.email ?? "").trim().toLowerCase(),
    tags: Array.isArray(inputs.tags)
      ? inputs.tags
      : String(inputs.tags ?? "").split(",").map((t) => t.trim()).filter(Boolean),
  }),

  validate: (inputs) => {
    const problems = [];
    if (!EMAIL_RE.test(inputs.email)) problems.push(`"${inputs.email}" is not an email address`);
    if (inputs.tags.length > 20) problems.push("at most 20 tags");
    return problems;
  },

  run: async (inputs, ctx) => {
    const res = await ctx.http.post(
      `${API}/contacts`,
      { email: inputs.email, name: inputs.name || undefined, tags: inputs.tags },
      { connection: "crm", throwOnError: false },
    );
    if (res.status === 409) {
      ctx.log.info("contact exists", { email: inputs.email });
      const found = await ctx.http.get(`${API}/contacts`, { connection: "crm", query: { email: inputs.email } });
      return { contact: found.json.items[0], created: false };
    }
    if (!res.ok) {
      throw new NodeError(`Acme CRM refused the contact: ${res.json?.message ?? res.status}`, {
        code: res.json?.code ?? `http_${res.status}`,
        details: { status: res.status },
        retryable: res.status >= 500 || res.status === 429,
      });
    }
    ctx.log.info("contact created", { id: res.json.id });
    return { contact: res.json, created: true };
  },

  output: (result) => ({ id: result.contact.id, email: result.contact.email, created: result.created }),
});
