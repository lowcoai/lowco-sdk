// A node library: the entry module exports its nodes (here as a library;
// named exports of defineNode values work too).
import { defineLibrary } from "@lowcoai/nodes";
import { createContact } from "./nodes/create-contact.mjs";
import { scoreLead } from "./nodes/score-lead.mjs";

export default defineLibrary({ nodes: [createContact, scoreLead] });
