/**
 * Bienestar App Logic
 * Pure JS with LocalStorage persistence & Supabase Sync
 */

console.log('app.js loaded');

// default supabase configuration (replace with your own project values)
const DEFAULT_SUPABASE_URL = 'https://qcbrxhuktglawmggdyge.supabase.co';
const DEFAULT_SUPABASE_KEY = 'sb_publishable_Uq-ovU5whLrT4ll0o1C1JA_XRpyPX-4';

const app = {
    data: {
        logs: [],
        medications: [],
        settings: {
            darkMode: false,
            unitWeight: 'kg',
            userName: '',
            targetWeight: 90,
            supabaseUrl: 'https://qcbrxhuktglawmggdyge.supabase.co',
            supabaseKey: 'sb_publishable_Uq-ovU5whLrT4ll0o1C1JA_XRpyPX-4'
        },
        user: null,
        syncing: false,
        authMode: 'login', // 'login' or 'signup'
    },

    supabase: null,
    deferredPrompt: null, // for PWA install

    init() {
        console.log('app.init() starting...');
        this.loadData();
        this.initSupabase();
        this.applyTheme();
        this.renderDashboard();
        this.renderHistory();
        this.renderSettings();
        this.renderMedications();
        this.initEventListeners();
        this.initCharts();

        // Set default date in modal
        const now = new Date();
        now.setMinutes(now.getMinutes() - now.getTimezoneOffset());
        const logDateInput = document.getElementById('log-date');
        if (logDateInput) logDateInput.value = now.toISOString().slice(0, 16);

        // Show auth modal on first launch if not authenticated
        if (!this.data.user && !localStorage.getItem('bienestar_auth_prompted')) {
            setTimeout(() => {
                this.showModal('auth-modal');
            }, 500);
        }

        console.log('Bienestar fully initialized');
    },

    loadData() {
        console.log('Loading local data...');
        // Load logs
        const savedLogs = localStorage.getItem('bienestar_logs');
        if (savedLogs) this.data.logs = JSON.parse(savedLogs);

        // Load medications
        const savedMeds = localStorage.getItem('bienestar_meds');
        if (savedMeds) this.data.medications = JSON.parse(savedMeds);

        // Load settings and merge with defaults
        const savedSettings = localStorage.getItem('bienestar_settings');
        if (savedSettings) {
            const parsed = JSON.parse(savedSettings);
            this.data.settings = { ...this.data.settings, ...parsed };
        }
        // ensure we always have supabase credentials set
        if (!this.data.settings.supabaseUrl) this.data.settings.supabaseUrl = DEFAULT_SUPABASE_URL;
        if (!this.data.settings.supabaseKey) this.data.settings.supabaseKey = DEFAULT_SUPABASE_KEY;
        this.saveSettings();
    },

    initSupabase() {
        const url = this.data.settings.supabaseUrl;
        const key = this.data.settings.supabaseKey;

        if (url && key) {
            try {
                if (typeof supabase === 'undefined') {
                    this.updateSyncIndicator('error');
                    return;
                }
                this.supabase = supabase.createClient(url, key);
                this.checkSession();
                this.updateSyncIndicator('synced');
            } catch (error) {
                console.error('Error creating Supabase client:', error);
                this.updateSyncIndicator('error');
            }
        } else {
            this.updateSyncIndicator('offline');
        }
    },

    async checkSession() {
        if (!this.supabase) return;
        try {
            const { data: { session } } = await this.supabase.auth.getSession();
            this.handleAuthStateChange(session);

            this.supabase.auth.onAuthStateChange((_event, session) => {
                this.handleAuthStateChange(session);
            });
        } catch (e) {
            console.error('Session check failed:', e);
        }
    },

    handleAuthStateChange(session) {
        this.data.user = session?.user || null;
        this.updateAuthUI();
        if (this.data.user) {
            this.pullFromRemote();
            this.pullMedsFromRemote();
        }
    },

    updateAuthUI() {
        const statusContainer = document.getElementById('auth-status-container');
        const infoContainer = document.getElementById('user-info-container');
        const emailDisplay = document.getElementById('user-email-display');

        if (this.data.user) {
            if (statusContainer) statusContainer.style.display = 'none';
            if (infoContainer) infoContainer.style.display = 'block';
            if (emailDisplay) emailDisplay.textContent = this.data.user.email;
            this.updateSyncIndicator('synced');
        } else {
            if (statusContainer) statusContainer.style.display = 'block';
            if (infoContainer) infoContainer.style.display = 'none';
            this.updateSyncIndicator('offline');
        }
    },

    toggleAuthMode() {
        this.data.authMode = this.data.authMode === 'login' ? 'signup' : 'login';
        document.getElementById('auth-title').textContent = this.data.authMode === 'login' ? 'Iniciar Sesión' : 'Registrarse';
        const submitBtn = document.getElementById('auth-submit-btn');
        if (submitBtn) submitBtn.textContent = this.data.authMode === 'login' ? 'Entrar' : 'Crear Cuenta';
        const switchBtn = document.getElementById('auth-switch-btn');
        if (switchBtn) switchBtn.textContent = this.data.authMode === 'login' ? '¿No tienes cuenta? Regístrate' : '¿Ya tienes cuenta? Entra';
    },

    async handleAuth(e) {
        e.preventDefault();
        if (!this.supabase) return alert('Por favor, configura Supabase primero en Ajustes.');

        const email = document.getElementById('auth-email').value;
        const password = document.getElementById('auth-password').value;
        const msg = document.getElementById('auth-message');
        if (msg) msg.textContent = 'Procesando...';

        try {
            let result;
            if (this.data.authMode === 'login') {
                result = await this.supabase.auth.signInWithPassword({ email, password });
            } else {
                result = await this.supabase.auth.signUp({ email, password });
            }

            if (result.error) throw result.error;

            // Mark that user has been authenticated
            localStorage.setItem('bienestar_auth_prompted', 'true');
            this.hideModal('auth-modal');
            if (msg) msg.textContent = '';
        } catch (error) {
            if (msg) msg.textContent = error.message;
        }
    },

    async signOut() {
        if (this.supabase) {
            await this.supabase.auth.signOut();
        }
        // Clear auth prompt flag so it asks again on next launch
        localStorage.removeItem('bienestar_auth_prompted');
    },

    saveSupabaseConfig() {
        const urlInput = document.getElementById('supabase-url');
        const keyInput = document.getElementById('supabase-key');

        const url = urlInput.value.trim();
        const key = keyInput.value.trim();

        if (!url || !key) {
            alert('Por favor, ingresa tanto la URL como la Anon Key.');
            return;
        }

        this.data.settings.supabaseUrl = url;
        this.data.settings.supabaseKey = key;

        this.saveSettings();
        this.initSupabase();
        alert('Configuración guardada correctamente.');
    },

    updateSyncIndicator(status) {
        const indicator = document.getElementById('sync-indicator');
        if (!indicator) return;

        indicator.className = 'sync-status ' + status;
        const icon = indicator.querySelector('i');

        if (icon) {
            if (status === 'synced') icon.setAttribute('data-lucide', 'cloud-check');
            else if (status === 'syncing') icon.setAttribute('data-lucide', 'refresh-cw');
            else if (status === 'error') icon.setAttribute('data-lucide', 'cloud-alert');
            else icon.setAttribute('data-lucide', 'cloud-off');
        }

        if (window.lucide) lucide.createIcons();
    },

    async pullFromRemote() {
        if (!this.supabase || !this.data.user) return;

        this.updateSyncIndicator('syncing');
        try {
            const { data, error } = await this.supabase
                .from('logs')
                .select('*')
                .order('date', { ascending: false });

            if (error) throw error;

            if (data) {
                this.data.logs = data;
                this.saveLogs();
                this.renderDashboard();
                this.renderHistory();
                this.updateChart();
            }
            this.updateSyncIndicator('synced');
        } catch (error) {
            console.error('Pull error:', error);
            this.updateSyncIndicator('error');
        }
    },

    async pushToRemote(logEntry) {
        if (!this.supabase || !this.data.user) return;

        this.updateSyncIndicator('syncing');
        try {
            const { error } = await this.supabase
                .from('logs')
                .upsert({ ...logEntry, user_id: this.data.user.id });

            if (error) throw error;
            this.updateSyncIndicator('synced');
        } catch (error) {
            console.error('Push error:', error);
            this.updateSyncIndicator('error');
        }
    },

    async deleteRemote(id) {
        if (!this.supabase || !this.data.user) return;
        try {
            await this.supabase.from('logs').delete().eq('id', id);
        } catch (e) {
            console.error('Delete error:', e);
        }
    },

    /**
     * Medications Management
     */
    async pullMedsFromRemote() {
        if (!this.supabase || !this.data.user) return;
        try {
            const { data, error } = await this.supabase
                .from('medications')
                .select('*');
            if (!error && data) {
                this.data.medications = data;
                this.saveMeds();
                this.renderMedications();
            }
        } catch (e) {
            console.error('Pull meds error:', e);
        }
    },

    renderMedications() {
        const medList = document.getElementById('med-list');
        if (!medList) return;

        if (this.data.medications.length === 0) {
            medList.innerHTML = '<p style="font-size: 0.8rem; opacity: 0.5; text-align: center;">No hay medicinas registradas.</p>';
            return;
        }

        medList.innerHTML = this.data.medications.map(med => `
            <div class="med-item">
                <span class="med-info">${med.name}</span>
                <button class="icon-btn" onclick="app.removeMedication(${med.id})" style="color: var(--accent-red); padding: 5px;">
                    <i data-lucide="x"></i>
                </button>
            </div>
        `).join('');
        if (window.lucide) lucide.createIcons();
    },

    async addMedication() {
        const input = document.getElementById('new-med-name');
        const name = input.value.trim();
        if (!name) return;

        const newMed = {
            id: Date.now(),
            name: name
        };

        this.data.medications.push(newMed);
        this.saveMeds();
        this.renderMedications();
        input.value = '';

        if (this.supabase && this.data.user) {
            await this.supabase.from('medications').upsert({ ...newMed, user_id: this.data.user.id });
        }
    },

    async removeMedication(id) {
        this.data.medications = this.data.medications.filter(m => m.id !== id);
        this.saveMeds();
        this.renderMedications();

        if (this.supabase && this.data.user) {
            await this.supabase.from('medications').delete().eq('id', id);
        }
    },

    saveMeds() {
        localStorage.setItem('bienestar_meds', JSON.stringify(this.data.medications));
    },

    /**
     * Calculations & UI
     */
    calculateAverages() {
        const now = new Date();
        const sevenDaysAgo = new Date(now.getTime() - (7 * 24 * 60 * 60 * 1000));
        const thirtyDaysAgo = new Date(now.getTime() - (30 * 24 * 60 * 60 * 1000));

        const getAvg = (logs) => {
            if (logs.length === 0) return { bp: '--/--', glucose: '--' };
            const sys = Math.round(logs.reduce((sum, l) => sum + l.systolic, 0) / logs.length);
            const dia = Math.round(logs.reduce((sum, l) => sum + l.diastolic, 0) / logs.length);
            const glucoseLogs = logs.filter(l => l.glucose);
            const glucose = glucoseLogs.length > 0
                ? Math.round(glucoseLogs.reduce((sum, l) => sum + l.glucose, 0) / glucoseLogs.length)
                : '--';
            return { bp: `${sys}/${dia}`, glucose };
        };

        const logs7 = this.data.logs.filter(l => new Date(l.date) >= sevenDaysAgo);
        const logs30 = this.data.logs.filter(l => new Date(l.date) >= thirtyDaysAgo);

        const avg7 = getAvg(logs7);
        const avg30 = getAvg(logs30);

        const el7bp = document.getElementById('avg-7-bp');
        const el7gl = document.getElementById('avg-7-glucose');
        const el30bp = document.getElementById('avg-30-bp');
        const el30gl = document.getElementById('avg-30-glucose');

        if (el7bp) el7bp.textContent = avg7.bp;
        if (el7gl) el7gl.textContent = `${avg7.glucose} mg/dL`;
        if (el30bp) el30bp.textContent = avg30.bp;
        if (el30gl) el30gl.textContent = `${avg30.glucose} mg/dL`;
    },

    applyTheme() {
        if (this.data.settings.darkMode) {
            document.body.classList.add('dark-mode');
            document.body.classList.remove('light-mode');
        } else {
            document.body.classList.remove('dark-mode');
            document.body.classList.add('light-mode');
        }
        const darkToggle = document.getElementById('dark-mode-toggle');
        if (darkToggle) darkToggle.checked = this.data.settings.darkMode;
        const themeBtn = document.getElementById('theme-toggle');
        if (themeBtn) {
            themeBtn.innerHTML = this.data.settings.darkMode ? '<i data-lucide="moon"></i>' : '<i data-lucide="sun"></i>';
        }
        if (window.lucide) lucide.createIcons();
    },

    toggleTheme() {
        this.data.settings.darkMode = !this.data.settings.darkMode;
        this.saveSettings();
        this.applyTheme();
        this.initCharts();
    },

    saveLogs() {
        localStorage.setItem('bienestar_logs', JSON.stringify(this.data.logs));
    },

    saveSettings() {
        localStorage.setItem('bienestar_settings', JSON.stringify(this.data.settings));
    },

    addLog(logEntry) {
        const entry = {
            id: Date.now(),
            ...logEntry
        };
        this.data.logs.unshift(entry);
        this.saveLogs();
        this.renderDashboard();
        this.renderHistory();
        this.updateChart();
        this.pushToRemote(entry);
    },

    deleteLog(id) {
        if (confirm('¿Estás seguro de que quieres eliminar este registro?')) {
            this.data.logs = this.data.logs.filter(l => l.id !== id);
            this.saveLogs();
            this.renderDashboard();
            this.renderHistory();
            this.updateChart();
            this.deleteRemote(id);
        }
    },

    getBPStatus(sys, dia) {
        if (sys >= 140 || dia >= 90) return { label: 'Etapa 2', class: 'status-high-2' };
        if (sys >= 130 || dia >= 80) return { label: 'Etapa 1', class: 'status-high-1' };
        if (sys >= 120 && dia < 80) return { label: 'Elevada', class: 'status-elevated' };
        return { label: 'Normal', class: 'status-normal' };
    },

    renderDashboard() {
        const lastLog = this.data.logs[0];
        const bpEl = document.getElementById('last-bp');
        const glucoseEl = document.getElementById('last-glucose');
        const weightEl = document.getElementById('last-weight');

        if (bpEl) bpEl.textContent = lastLog ? `${lastLog.systolic}/${lastLog.diastolic}` : '--/--';
        if (glucoseEl) glucoseEl.textContent = lastLog && lastLog.glucose ? lastLog.glucose : '--';
        if (weightEl) weightEl.textContent = lastLog && lastLog.weight ? Number(lastLog.weight).toFixed(1) : '--.-';

        this.calculateAverages();

        const listContainer = document.getElementById('recent-logs-list');
        if (listContainer) {
            listContainer.innerHTML = this.data.logs.slice(0, 5).map(log => {
                const status = this.getBPStatus(log.systolic, log.diastolic);
                return `
                <div class="history-item">
                    <div class="history-info">
                        <div class="date">${new Date(log.date).toLocaleDateString('es-ES', { day: 'numeric', month: 'short', hour: '2-digit', minute: '2-digit' })}</div>
                        <div class="type">
                            <span class="history-status ${status.class}"></span>
                            Presión: ${log.systolic}/${log.diastolic}
                        </div>
                    </div>
                    <div class="history-values">
                        ${log.glucose ? `<span>${log.glucose} mg/dL</span>` : ''}
                        ${log.weight ? `<span style="margin-left: 10px">${log.weight}kg</span>` : ''}
                    </div>
                </div>
                `;
            }).join('');
        }
    },

    renderHistory() {
        const fullList = document.getElementById('full-history-list');
        if (!fullList) return;

        // Add user name for print
        const historyView = document.getElementById('history');
        if (historyView) historyView.setAttribute('data-user', this.data.settings.userName || '');

        if (this.data.logs.length === 0) {
            fullList.innerHTML = '<div class="glass" style="padding: 2rem; text-align: center; opacity: 0.6;">No hay registros aún.</div>';
            return;
        }

        fullList.innerHTML = this.data.logs.map(log => {
            const status = this.getBPStatus(log.systolic, log.diastolic);
            return `
            <div class="history-card glass" id="item-${log.id}">
                <div class="history-details">
                    <div class="date">${new Date(log.date).toLocaleDateString('es-ES', { weekday: 'long', day: 'numeric', month: 'long', hour: '2-digit', minute: '2-digit' })}</div>
                    <div style="font-weight: 700; font-size: 1.1rem; display: flex; align-items: center; gap: 0.5rem;">
                        <span class="history-status ${status.class}"></span>
                        ${log.systolic}/${log.diastolic} <small style="font-weight: 400; font-size: 0.8rem; opacity: 0.7;">(${status.label})</small>
                    </div>
                    <div style="font-size: 0.9rem; opacity: 0.8;">
                        ${log.pulse ? `Pulso: ${log.pulse} LPM | ` : ''}
                        ${log.glucose ? `Glicemia: ${log.glucose} mg/dL | ` : ''}
                        ${log.weight ? `Peso: ${log.weight} kg` : ''}
                    </div>
                </div>
                <button class="icon-btn" onclick="app.deleteLog(${log.id})" style="color: var(--accent-red)">
                    <i data-lucide="trash-2"></i>
                </button>
            </div>
            `;
        }).join('');
        if (window.lucide) lucide.createIcons();
    },

    renderSettings() {
        const nameEl = document.getElementById('user-name');
        const weightEl = document.getElementById('target-weight');
        const urlEl = document.getElementById('supabase-url');
        const keyEl = document.getElementById('supabase-key');
        const saveConfigBtn = document.getElementById('save-supabase-config');

        if (nameEl) nameEl.value = this.data.settings.userName || '';
        if (weightEl) weightEl.value = this.data.settings.targetWeight || 90;
        if (urlEl) {
            urlEl.value = this.data.settings.supabaseUrl || '';
            urlEl.disabled = true;
        }
        if (keyEl) {
            keyEl.value = this.data.settings.supabaseKey || '';
            keyEl.disabled = true;
        }
        if (saveConfigBtn) saveConfigBtn.style.display = 'none';
    },

    initCharts() {
        const canvas = document.getElementById('healthChart');
        if (!canvas) return;
        if (this.chart) this.chart.destroy();
        const ctx = canvas.getContext('2d');
        if (!ctx) return;
        const isDark = document.body.classList.contains('dark-mode');
        const textColor = isDark ? '#f1f5f9' : '#1e293b';
        if (typeof Chart === 'undefined') return;

        this.chart = new Chart(ctx, {
            type: 'line',
            data: { labels: [], datasets: [] },
            options: {
                responsive: true, maintainAspectRatio: false,
                plugins: { legend: { labels: { color: textColor, font: { family: 'Inter', size: 12 } } } },
                scales: {
                    y: { ticks: { color: textColor }, grid: { color: isDark ? 'rgba(255,255,255,0.05)' : 'rgba(0,0,0,0.05)' } },
                    x: { ticks: { color: textColor }, grid: { display: false } }
                }
            }
        });
        this.updateChart();
    },

    updateChart() {
        if (!this.chart) return;
        const filterEl = document.getElementById('chart-filter');
        if (!filterEl) return;
        const filter = filterEl.value;
        const sortedLogs = [...this.data.logs].reverse().slice(-7);
        const labels = sortedLogs.map(l => new Date(l.date).toLocaleDateString('es-ES', { day: 'numeric', month: 'short' }));
        let datasets = [];
        const isDark = document.body.classList.contains('dark-mode');

        if (filter === 'bp') {
            datasets = [
                { label: 'Sistólica', data: sortedLogs.map(l => l.systolic), borderColor: '#4f46e5', backgroundColor: 'rgba(79, 70, 229, 0.1)', tension: 0.4, fill: true },
                { label: 'Diastólica', data: sortedLogs.map(l => l.diastolic), borderColor: '#10b981', backgroundColor: 'transparent', tension: 0.4 }
            ];
        } else if (filter === 'glucose') {
            datasets = [{ label: 'Glicemia', data: sortedLogs.map(l => l.glucose), borderColor: '#ef4444', backgroundColor: 'rgba(239, 68, 68, 0.1)', tension: 0.4, fill: true }];
        } else if (filter === 'weight') {
            datasets = [{ label: 'Peso', data: sortedLogs.map(l => l.weight), borderColor: '#3b82f6', backgroundColor: 'rgba(59, 130, 246, 0.1)', tension: 0.4, fill: true }];
        }

        this.chart.data.labels = labels;
        this.chart.data.datasets = datasets;
        const textColor = isDark ? '#f1f5f9' : '#1e293b';
        if (this.chart.options.plugins.legend.labels) this.chart.options.plugins.legend.labels.color = textColor;
        if (this.chart.options.scales.x.ticks) this.chart.options.scales.x.ticks.color = textColor;
        if (this.chart.options.scales.y.ticks) this.chart.options.scales.y.ticks.color = textColor;
        this.chart.update();
    },

    showModal(id) {
        const modal = document.getElementById(id);
        if (modal) modal.classList.add('active');
    },

    hideModal(id) {
        const modal = document.getElementById(id);
        if (modal) modal.classList.remove('active');
    },

    switchView(viewId) {
        document.querySelectorAll('.view').forEach(v => v.classList.remove('active'));
        const viewEl = document.getElementById(viewId);
        if (viewEl) viewEl.classList.add('active');
        document.querySelectorAll('.nav-item').forEach(n => n.classList.remove('active'));
        const navEl = document.getElementById(`nav-${viewId}`);
        if (navEl) navEl.classList.add('active');
        if (viewId === 'dashboard') this.updateChart();
        if (viewId === 'history') this.renderHistory();
        window.scrollTo(0, 0);
    },

    initEventListeners() {
        const themeBtn = document.getElementById('theme-toggle');
        if (themeBtn) themeBtn.addEventListener('click', () => this.toggleTheme());

        const form = document.getElementById('health-form');
        if (form) {
            form.addEventListener('submit', (e) => {
                e.preventDefault();
                // Build formData with only filled fields
                const formData = {
                    date: document.getElementById('log-date').value,
                    systolic: parseInt(document.getElementById('systolic').value),
                    diastolic: parseInt(document.getElementById('diastolic').value)
                };
                // Add optional fields only if they have values
                const pulseVal = parseInt(document.getElementById('pulse').value);
                if (!isNaN(pulseVal)) formData.pulse = pulseVal;
                
                const glucoseVal = parseInt(document.getElementById('glucose').value);
                if (!isNaN(glucoseVal)) formData.glucose = glucoseVal;
                
                const weightVal = parseFloat(document.getElementById('weight').value);
                if (!isNaN(weightVal)) formData.weight = weightVal;
                
                this.addLog(formData);
                this.hideModal('log-modal');
                form.reset();
            });
        }

        const authForm = document.getElementById('auth-form');
        if (authForm) authForm.addEventListener('submit', (e) => this.handleAuth(e));

        const filter = document.getElementById('chart-filter');
        if (filter) filter.addEventListener('change', () => this.updateChart());

        const nameInput = document.getElementById('user-name');
        if (nameInput) {
            nameInput.addEventListener('change', (e) => {
                this.data.settings.userName = e.target.value;
                this.saveSettings();
                this.renderHistory(); // Refresh user name in report
            });
        }

        const targetWeightInput = document.getElementById('target-weight');
        if (targetWeightInput) {
            targetWeightInput.addEventListener('change', (e) => {
                this.data.settings.targetWeight = parseFloat(e.target.value);
                this.saveSettings();
            });
        }

        const saveConfigBtn = document.getElementById('save-supabase-config');
        if (saveConfigBtn) {
            saveConfigBtn.addEventListener('click', (e) => {
                e.preventDefault();
                this.saveSupabaseConfig();
            });
        }

        // handle install button click
        const installBtn = document.getElementById('install-btn');
        if (installBtn) {
            installBtn.addEventListener('click', async () => {
                if (!this.deferredPrompt) return;
                this.deferredPrompt.prompt();
                const choice = await this.deferredPrompt.userChoice;
                // hide button after prompt
                installBtn.style.display = 'none';
                this.deferredPrompt = null;
            });
        }
    }
};

window.app = app;

function startApp() {
    if (window.appStarted) return;
    window.appStarted = true;
    app.init();
}

if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', startApp);
} else {
    startApp();
}

// Service Worker Registration
if ('serviceWorker' in navigator) {
    window.addEventListener('load', () => {
        navigator.serviceWorker.register('./sw.js')
            .then(reg => console.log('Service Worker registered', reg))
            .catch(err => console.error('Service Worker registration failed', err));
    });
}
