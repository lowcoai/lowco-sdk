import { defineNode } from "@lowcoai/nodes";

const INDUSTRY_WEIGHT = { saas: 1.2, retail: 0.9, manufacturing: 1.0, other: 0.8 };

// A pure computation: no HTTP, just inputs to output.
export const scoreLead = defineNode({
  key: "acme_score_lead",
  name: "Score lead",
  description: "Scores a lead from 0 to 100 and grades it A-D.",
  category: "Acme CRM",
  icon: "gauge",
  inputs: [
    { name: "employees", displayName: "Employees", type: "number", required: true },
    { name: "budget", displayName: "Budget (USD)", type: "number" },
    {
      name: "industry",
      displayName: "Industry",
      type: "options",
      default: "other",
      options: Object.keys(INDUSTRY_WEIGHT).map((id) => ({ id, label: id[0].toUpperCase() + id.slice(1) })),
    },
  ],
  outputSchema: {
    type: "object",
    properties: { score: { type: "number" }, grade: { enum: ["A", "B", "C", "D"] } },
    required: ["score", "grade"],
  },
  strictOutput: true,

  input: (inputs) => ({
    employees: Number(inputs.employees),
    budget: Number(inputs.budget ?? 0),
    industry: inputs.industry in INDUSTRY_WEIGHT ? inputs.industry : "other",
  }),
  validate: (inputs) => {
    if (!Number.isFinite(inputs.employees) || inputs.employees < 0) return "employees must be a number of at least 0";
  },
  run: (inputs) => {
    const size = Math.min(50, Math.log10(inputs.employees + 1) * 15);
    const money = Math.min(50, inputs.budget / 2000);
    const score = Math.round(Math.min(100, (size + money) * INDUSTRY_WEIGHT[inputs.industry]));
    return { score, grade: score >= 75 ? "A" : score >= 50 ? "B" : score >= 25 ? "C" : "D" };
  },
});
