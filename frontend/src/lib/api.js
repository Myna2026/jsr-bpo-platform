/**
 * API Client — verbindet das Frontend mit dem FastAPI Backend
 * Fallback auf Mock-Daten wenn Backend nicht erreichbar
 */

const API_BASE = import.meta?.env?.VITE_API_URL || 'http://localhost:8000/api/v1';

class ApiClient {
  async get(path, params = {}) {
    const url = new URL(`${API_BASE}${path}`);
    Object.entries(params).forEach(([k, v]) => {
      if (Array.isArray(v)) v.forEach(val => url.searchParams.append(k, val));
      else if (v !== null && v !== undefined) url.searchParams.append(k, v);
    });
    const resp = await fetch(url.toString());
    if (!resp.ok) throw new Error(`API ${resp.status}: ${path}`);
    return resp.json();
  }

  async patch(path, body = {}) {
    const resp = await fetch(`${API_BASE}${path}`, {
      method: 'PATCH',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(body),
    });
    if (!resp.ok) throw new Error(`PATCH ${resp.status}: ${path}`);
    return resp.json();
  }

  async post(path, body = {}) {
    const resp = await fetch(`${API_BASE}${path}`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(body),
    });
    if (!resp.ok) throw new Error(`POST ${resp.status}: ${path}`);
    return resp.json();
  }

  // ── Companies ──────────────────────────────────────────
  async getCompanies(filters = {}, sort = {}, page = 1, pageSize = 50) {
    return this.get('/companies', {
      ...filters,
      sort_by: sort.by || 'score',
      sort_dir: sort.dir || 'desc',
      page,
      page_size: pageSize,
    });
  }

  async getCompany(id) {
    return this.get(`/companies/${id}`);
  }

  async updateStatus(id, status) {
    return this.patch(`/companies/${id}/status`, null, `?status=${status}`);
  }

  async updatePriority(id, priority) {
    return this.patch(`/companies/${id}/priority`, null, `?priority=${priority}`);
  }

  // ── Contacts ───────────────────────────────────────────
  async getContacts(companyId) {
    return this.get(`/contacts/company/${companyId}`);
  }

  // ── Jobs ───────────────────────────────────────────────
  async getJobs(companyId) {
    return this.get(`/jobs/company/${companyId}`);
  }

  async getGrowthSignals(limit = 50) {
    return this.get('/jobs/signals', { limit });
  }

  // ── Activities ─────────────────────────────────────────
  async getActivities(companyId) {
    return this.get(`/activities/company/${companyId}`);
  }

  async createActivity(payload) {
    return this.post('/activities', payload);
  }

  async getDueToday() {
    return this.get('/activities/due-today');
  }

  // ── Crawler ────────────────────────────────────────────
  async triggerSeedImport() {
    return this.post('/crawler/seed-import');
  }

  async triggerJobScan() {
    return this.post('/crawler/job-scan');
  }

  async enrichCompany(id) {
    return this.post(`/crawler/enrich/${id}`);
  }

  // ── Export ─────────────────────────────────────────────
  exportCsv(filters = {}, includeContacts = false) {
    const url = new URL(`${API_BASE}/export/companies/csv`);
    Object.entries(filters).forEach(([k, v]) => {
      if (Array.isArray(v)) v.forEach(val => url.searchParams.append(k, val));
      else if (v != null) url.searchParams.append(k, v);
    });
    if (includeContacts) url.searchParams.append('include_contacts', 'true');
    window.open(url.toString(), '_blank');
  }
}

export const api = new ApiClient();

// ── React Hook ─────────────────────────────────────────────
import { useState, useEffect, useCallback } from 'react';

export function useCompanies(filters, sort, page, pageSize = 50) {
  const [data, setData] = useState(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);

  const load = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      const result = await api.getCompanies(filters, sort, page, pageSize);
      setData(result);
    } catch (e) {
      setError(e.message);
      // Fallback auf Mock-Daten
      console.warn('Backend nicht erreichbar — Mock-Daten werden verwendet');
    } finally {
      setLoading(false);
    }
  }, [JSON.stringify(filters), JSON.stringify(sort), page, pageSize]);

  useEffect(() => { load(); }, [load]);

  return { data, loading, error, reload: load };
}
