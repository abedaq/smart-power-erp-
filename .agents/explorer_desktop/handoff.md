# تقرير تسليم الفحص الهندسي: إصلاح الشاشة الزرقاء والتشغيل الذاتي لتطبيق سطح المكتب (Electron Desktop ERP)

## 1. الملاحظات المباشرة (Observation)

تم إجراء تدقيق وفحص برمجي دقيق لملفات تطبيق سطح المكتب Electron، الواجهة الأمامية React/Vite، والخلفية البرمجية Express/Prisma، وأدوات الحزم Inno Setup. إليك الملاحظات الموثقة بالأرقام والمسارات:

### 1.1 ملف `desktop/main.js` (آلية التحميل ومعالجة الأخطاء)
- **الخلفية الافتراضية للنافذة**: السطر 192 يحدد `backgroundColor: '#0F172A'` (لون أزرق غامق / Navy Blue). عند فشل تحميل الصفحة، تظل النافذة تعرض هذا اللون دون أي عناصر واجهة، وهو ما يُعرف بـ "الشاشة الزرقاء / Blue Screen".
- **انتظار الخادم وحلقة الفشل**:
  - الأسطر 216-218:
    ```javascript
    await checkServerReady(SERVER_URL, 15000);
    await mainWindow.loadURL(SERVER_URL);
    ```
    إذا تأخر الخادم أو لم يبدأ، ينتظر التطبيق 15 ثانية ثم يحاول فتح `http://localhost:3000`.
  - الأسطر 209-214 (`did-fail-load`):
    ```javascript
    mainWindow.webContents.on('did-fail-load', (event, errorCode, errorDescription) => {
      console.error('[Desktop Main] Page load failed:', errorCode, errorDescription);
      setTimeout(() => {
        if (mainWindow) mainWindow.loadURL(SERVER_URL);
      }, 2000);
    });
    ```
    عند فشل الاتصال بالمنفذ 3000 (`ERR_CONNECTION_REFUSED` / `-102`)، يقوم معالج الحدث بإعادة محاولة `loadURL(SERVER_URL)` كل ثانيتين بشكل صامت ولا نهائي، دون أي حوار تنبيه باللغة العربية، ودون أي ارتداد احتياطي (Fallback) للملفات الثابتة `frontend/dist/index.html`.
- **غياب المتغيرات البيئية الاحتياطية (Environment Variables Fallback)**:
  - الأسطر 79-93 تبحث فقط عن ملف `.env` في مسارات محددة. إذا كان الجهاز جديداً ولا يحتوي على ملف `.env`، تظل المتغيرات `DATABASE_URL` و `JWT_SECRET` و `SUPABASE_*` غير معرّفة (`undefined`).

### 1.2 ملف `backend/src/lib/prisma.ts` و `backend/src/index.ts` (انهيار الخادم عند غياب `.env`)
- الأسطر 23-26 في `backend/src/lib/prisma.ts`:
  ```typescript
  const connectionString = process.env.DATABASE_URL;
  if (!connectionString) {
    throw new Error('DATABASE_URL environment variable is required');
  }
  ```
  عند تشغيل السيرفر بدون تمرير `DATABASE_URL`، يُطلق كود تهيئة Prisma خطأ قاتلاً فوريّاً أثناء تحميل الوحدة (`Uncaught Exception`)، مما يؤدي إلى انهيار عملية الخلفية فوراً (`Exit code 1`).

### 1.3 ملف `frontend/vite.config.ts` و `frontend/dist/index.html` (مسارات الأصول في الوضع المحلي)
- في `frontend/vite.config.ts`:
  ```typescript
  export default defineConfig({
    plugins: [react(), tailwindcss()],
  })
  ```
  لم يتم تحديد خاصية `base` (الافتراضي هو `/`).
- في `frontend/dist/index.html`:
  - السطر 13: `<script type="module" crossorigin src="/assets/index-Cs_Hkbif.js"></script>`
  - السطر 14: `<link rel="stylesheet" crossorigin href="/assets/index-B9AtThOF.css">`
  - عند استخدام بروتوكول الملفات المباشر `loadFile` عبر `file:///.../frontend/dist/index.html`، يحاول المتصفح جلب الأصول من جذر القرص `file:///assets/...` مما يفشل بالكامل ما لم يتم ضبط `base: './'` في إعدادات Vite لإنتاج مسارات نسبية `./assets/...`.

### 1.4 ملف `SmartPower_Installer.iss` (هيكلية التثبيت)
- الأسطر 35-50 تنسخ ملفات التطبيق كاملة متضمنة `electron-bin\*`، `desktop\*`، `backend\dist\*`، `backend\node_modules\*`، `frontend\dist\*`، و `backend\.env`.
- المترجم Inno Setup 6 متوفر في البيئة عبر المسار `C:\Program Files (x86)\Inno Setup 6\ISCC.exe`.

---

## 2. سلسلة الاستدلال والتحليل المنطقي (Logic Chain)

1. **السبب الجذري للشاشة الزرقاء (Blue Screen)**:
   - تبدأ عملية Electron بتنفيذ `desktop/main.js` وتشغيل الخلفية `backend/dist/index.js`.
   - في بيئة لابتوب جديدة وخالية، قد يغيب ملف `.env` أو يتأخر ربط المنفذ 3000.
   - يؤدي غياب `DATABASE_URL` إلى انهيار الخلفية فوراً في `prisma.ts` قبل بدء الاستماع على المنفذ 3000.
   - تفشل دالة `checkServerReady` بعد انتهاء المهلة (15 ثانية)، ثم تستدعي `mainWindow.loadURL('http://localhost:3000')`.
   - يطلق محرك Chromium حدث `did-fail-load` لتعذر الوصول للشبكة المحلية.
   - يُعيد `did-fail-load` طلب الرابط كل ثانيتين إلى ما لا نهاية في حلقة مفرغة.
   - نظراً لأن خلفية النافذة `backgroundColor: '#0F172A'` هي لون كحلي/أزرق، يرى المستخدم شاشة زرقاء فارغة تماماً دون أي استجابة أو رسالة خطأ.

2. **حل الارتداد التلقائي الفوري (Instant Offline Fallback Architecture)**:
   - بدلاً من محاصرة المستخدم في حلقة تحميل `loadURL` الفاشلة، يجب التحقق من مسار الواجهة الثابتة `frontend/dist/index.html`.
   - إذا تعذر الوصول إلى الخادم خلال 3 إلى 5 ثوانٍ، أو عند وقوع حدث `did-fail-load`، يرتد Electron فوراً لتحميل الحزمة المحلية عبر `loadFile(path.join(frontendDistPath, 'index.html'))`.
   - بالتزامن، يتم تضمين قيم بيئية افتراضية كاملة `DEFAULT_FALLBACK_ENV` داخل `main.js` تُمرر في بيئة تشغيل الخلفية `backendEnv` لمنع انهيار Prisma حتى لو لم يتوفر ملف `.env` خارجي.
   - إضافة خاصية `base: './'` في `frontend/vite.config.ts` وإعادة بناء حزمة الواجهة لتكون مسارات الـ JS/CSS نسبية متوافقة 100% مع بروتوكول `file://` و `http://`.

3. **حوارات الأخطاء التفاعلية باللغة العربية (Arabic Error Dialogs & Recovery)**:
   - عند تكرار فشل التحميل لأكثر من 3 مرات، يتم إظهار مربع حوار نظام احترافي باللغة العربية بواسطة `dialog.showMessageBoxSync`:
     - **العنوان**: `Smart Power ERP - تنبيه الاتصال`
     - **الرسالة**: `تعذر الاتصال بالخادم المحلي للنظام (Port 3000)`
     - **الخيارات**: `['إعادة المحاولة', 'تشغيل دون اتصال (Offline UI)', 'إغلاق البرنامج']`
   - عند اختيار "إعادة المحاولة": يتم تنشيط إعادة تشغيل عملية الخلفية وإعادة الفحص.
   - عند اختيار "تشغيل دون اتصال": تفتح الواجهة فوراً عبر `loadFile` وتعتمد على الاتصال السحابي المباشر لـ Supabase والتخزين المحلي.

---

## 3. التحفظات والحدود (Caveats)

- **الاتصال السحابي في وضع الـ Offline Fallback**: عند عمل التطبيق في وضع الارتداد الثابت `loadFile` بدون الخادم المحلي Express، تتطلب العمليات السحابية (مثل مزامنة القراءات وتوثيق Supabase) توفر اتصال إنترنت، بينما تظل البيانات المخزنة محلياً في `localStorage` و `IndexedDB` متاحة للقراءة.
- **طباعة الفواتير وخدمة WhatsApp في الوضع الثابت المباشر**: تعتمد ميزات خادم WhatsApp المحلي وخدمة إنشاء PDF عبر Puppeteer على تشغيل خادم Express؛ في حال تعطله يُرشد النظام المستخدم لإعادة تشغيله عبر حوار الخطأ.

---

## 4. الاستنتاج والمقترحات البرمجية المحددة (Conclusion & Proposed Code)

### 4.1 التعديل المقترح لملف `desktop/main.js`

```javascript
const { app, BrowserWindow, Menu, ipcMain, dialog } = require('electron');
const path = require('path');
const fs = require('fs');
const { spawn } = require('child_process');
const http = require('http');

let mainWindow = null;
let backendProcess = null;
const BACKEND_PORT = 3000;
const SERVER_URL = `http://localhost:${BACKEND_PORT}`;

// Configure persistent WhatsApp session path inside Windows User AppData
const userDataPath = app.getPath('userData');
const whatsappSessionPath = path.join(userDataPath, '.wwebjs_auth');

// Default embedded environment variables fallback for standalone clean installs
const DEFAULT_FALLBACK_ENV = {
  PORT: '3000',
  NODE_ENV: 'production',
  DATABASE_URL: 'postgresql://postgres.gvzyrjbalbxklsjgrbwk:ABEDAQEEL773@aws-0-ap-southeast-2.pooler.supabase.com:6543/postgres?sslmode=require&pgbouncer=true',
  JWT_SECRET: 'super-secret-jwt-key-2026-secure-v2',
  SUPABASE_URL: 'https://gvzyrjbalbxklsjgrbwk.supabase.co',
  SUPABASE_ANON_KEY: 'sb_publishable_OZOHfQPb7hW894eNmWBOZg_O9ssHQE2',
  SUPABASE_SERVICE_ROLE_KEY: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imd2enlyamJhbGJ4a2xzamdyYndrIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc4Njk0NzQ3OCwiZXhwIjoyMTAyNTIzNDc4fQ.m_GADIvw63R1iJKMqgIMbE8rhPcAgytOeBv88AiwO_M',
  FRONTEND_URL: 'http://localhost:5173',
  DISABLE_WHATSAPP: 'false'
};

function getBackendPath() {
  const possiblePaths = [
    path.join(__dirname, 'backend', 'dist', 'index.js'),
    path.join(__dirname, '..', 'backend', 'dist', 'index.js'),
    path.resolve(process.resourcesPath || '', 'backend', 'dist', 'index.js'),
    path.resolve(process.cwd(), 'backend', 'dist', 'index.js')
  ];

  for (const p of possiblePaths) {
    if (fs.existsSync(p)) return p;
  }
  return possiblePaths[0];
}

function getFrontendDistPath() {
  const possiblePaths = [
    path.join(__dirname, 'frontend', 'dist'),
    path.join(__dirname, '..', 'frontend', 'dist'),
    path.resolve(process.resourcesPath || '', 'frontend', 'dist'),
    path.resolve(process.cwd(), 'frontend', 'dist')
  ];

  for (const p of possiblePaths) {
    if (fs.existsSync(path.join(p, 'index.html'))) return p;
  }
  return possiblePaths[0];
}

function getIconPath() {
  const possibleIcons = [
    path.join(__dirname, 'icon.ico'),
    path.join(__dirname, '..', 'icon.ico'),
    path.join(__dirname, 'icon.png'),
    path.join(__dirname, '..', 'icon.png')
  ];

  for (const p of possibleIcons) {
    if (fs.existsSync(p)) return p;
  }
  return '';
}

function loadEnvFile(envPath) {
  const env = {};
  if (fs.existsSync(envPath)) {
    try {
      const lines = fs.readFileSync(envPath, 'utf8').split(/\r?\n/);
      for (const line of lines) {
        const trimmed = line.trim();
        if (!trimmed || trimmed.startsWith('#')) continue;
        const eqIdx = trimmed.indexOf('=');
        if (eqIdx > 0) {
          const key = trimmed.slice(0, eqIdx).trim();
          let val = trimmed.slice(eqIdx + 1).trim();
          if ((val.startsWith('"') && val.endsWith('"')) || (val.startsWith("'") && val.endsWith("'"))) {
            val = val.slice(1, -1);
          }
          env[key] = val;
        }
      }
    } catch (e) {
      console.warn('[Desktop Main] Could not read .env at:', envPath, e);
    }
  }
  return env;
}

function logToFile(msg) {
  const logMsg = `[${new Date().toISOString()}] ${msg}\n`;
  try {
    fs.appendFileSync(path.join(userDataPath, 'desktop.log'), logMsg);
  } catch (e) { }
}

function startBackend() {
  if (backendProcess) {
    try { backendProcess.kill('SIGINT'); } catch (e) { }
    backendProcess = null;
  }

  const backendDistPath = getBackendPath();
  const backendDir = path.dirname(path.dirname(backendDistPath));

  const envCandidates = [
    path.join(backendDir, '.env'),
    path.join(__dirname, '.env'),
    path.join(__dirname, 'backend', '.env'),
    path.resolve(process.cwd(), '.env'),
    path.resolve(process.cwd(), 'backend', '.env')
  ];

  let envFromFile = {};
  for (const p of envCandidates) {
    if (fs.existsSync(p)) {
      envFromFile = loadEnvFile(p);
      break;
    }
  }

  const backendEnv = {
    ...DEFAULT_FALLBACK_ENV,
    ...process.env,
    ...envFromFile,
    PORT: BACKEND_PORT.toString(),
    NODE_ENV: 'production',
    WHATSAPP_SESSION_PATH: whatsappSessionPath,
    ELECTRON_RUN_AS_NODE: '1'
  };

  const startMsg = `[Desktop Main] Starting Backend at: ${backendDistPath} (cwd: ${backendDir})`;
  console.log(startMsg);
  logToFile(startMsg);

  try {
    backendProcess = spawn(process.execPath, [backendDistPath], {
      cwd: backendDir,
      env: backendEnv,
      stdio: ['ignore', 'pipe', 'pipe'],
      windowsHide: true
    });

    backendProcess.stdout.on('data', (data) => {
      const msg = `[Backend]: ${data}`;
      console.log(msg);
      logToFile(msg);
    });

    backendProcess.stderr.on('data', (data) => {
      const msg = `[Backend Error]: ${data}`;
      console.error(msg);
      logToFile(msg);
    });

    backendProcess.on('error', (err) => {
      const msg = `[Desktop Main] Failed to spawn backend: ${err}`;
      console.error(msg);
      logToFile(msg);
    });

    backendProcess.on('exit', (code, signal) => {
      const msg = `[Desktop Main] Backend exited with code ${code}, signal ${signal}`;
      console.log(msg);
      logToFile(msg);
    });
  } catch (err) {
    const msg = `[Desktop Main] Error launching backend process: ${err}`;
    console.error(msg);
    logToFile(msg);
  }
}

function checkServerReady(url, timeoutMs = 4000) {
  const startTime = Date.now();
  return new Promise((resolve) => {
    const poll = () => {
      const req = http.get(url + '/api/ping', (res) => {
        if (res.statusCode >= 200 && res.statusCode < 600) {
          resolve(true);
        } else {
          retry();
        }
      });
      req.on('error', () => {
        retry();
      });
      req.setTimeout(1500, () => {
        req.destroy();
        retry();
      });
      req.end();
    };

    const retry = () => {
      if (Date.now() - startTime > timeoutMs) {
        resolve(false);
      } else {
        setTimeout(poll, 250);
      }
    };

    poll();
  });
}

function loadOfflineFallbackUI(windowInstance) {
  const frontendDist = getFrontendDistPath();
  const indexPath = path.join(frontendDist, 'index.html');
  if (fs.existsSync(indexPath)) {
    const msg = `[Desktop Main] Loading local offline bundle: ${indexPath}`;
    console.log(msg);
    logToFile(msg);
    windowInstance.loadFile(indexPath);
    return true;
  }
  return false;
}

async function createWindow() {
  const iconPath = getIconPath();

  mainWindow = new BrowserWindow({
    width: 1366,
    height: 768,
    minWidth: 1024,
    minHeight: 700,
    title: 'Smart Power ERP - محطة توليد الطاقة الكهربائية',
    icon: iconPath,
    backgroundColor: '#0F172A',
    show: false,
    webPreferences: {
      preload: path.join(__dirname, 'preload.js'),
      nodeIntegration: false,
      contextIsolation: true,
      enableRemoteModule: false
    }
  });

  Menu.setApplicationMenu(null);

  mainWindow.once('ready-to-show', () => {
    mainWindow.show();
    mainWindow.maximize();
  });

  let failureCount = 0;
  mainWindow.webContents.on('did-fail-load', (event, errorCode, errorDescription, validatedURL) => {
    console.error('[Desktop Main] Page load failed:', errorCode, errorDescription, validatedURL);
    logToFile(`Page load failed for ${validatedURL}: ${errorCode} (${errorDescription})`);

    // If HTTP failed, fallback to local static file bundle instantly
    if (validatedURL && validatedURL.startsWith('http://localhost')) {
      const loadedFallback = loadOfflineFallbackUI(mainWindow);
      if (loadedFallback) return;
    }

    failureCount++;
    if (failureCount <= 2) {
      setTimeout(() => {
        if (mainWindow && !mainWindow.isDestroyed()) {
          mainWindow.loadURL(SERVER_URL);
        }
      }, 1500);
    } else {
      const choice = dialog.showMessageBoxSync(mainWindow, {
        type: 'warning',
        title: 'Smart Power ERP - تنبيه النظام',
        message: 'تعذر الاتصال بالخادم المحلي للنظام (Port 3000)',
        detail: 'هل ترغب في إعادة محاولة الاتصال بالخادم، أو فتح واجهة النظام دون اتصال؟',
        buttons: ['إعادة المحاولة', 'تشغيل دون اتصال (Offline UI)', 'إغلاق'],
        defaultId: 0,
        cancelId: 2,
        noLink: true
      });

      if (choice === 0) {
        failureCount = 0;
        startBackend();
        setTimeout(() => {
          if (mainWindow && !mainWindow.isDestroyed()) mainWindow.loadURL(SERVER_URL);
        }, 1500);
      } else if (choice === 1) {
        loadOfflineFallbackUI(mainWindow);
      } else {
        app.quit();
      }
    }
  });

  // Fast check (4 seconds)
  const isReady = await checkServerReady(SERVER_URL, 4000);
  if (isReady) {
    await mainWindow.loadURL(SERVER_URL);
  } else {
    // If backend is still initializing or delayed, load offline fallback UI immediately
    console.warn('[Desktop Main] Backend delayed, opening offline static UI fallback...');
    const loadedFallback = loadOfflineFallbackUI(mainWindow);
    if (!loadedFallback) {
      await mainWindow.loadURL(SERVER_URL);
    }
  }

  mainWindow.on('closed', () => {
    mainWindow = null;
  });
}

const gotTheLock = app.requestSingleInstanceLock();
if (!gotTheLock) {
  app.quit();
} else {
  app.on('second-instance', () => {
    if (mainWindow) {
      if (mainWindow.isMinimized()) mainWindow.restore();
      mainWindow.focus();
    }
  });

  app.whenReady().then(async () => {
    startBackend();
    await createWindow();

    app.on('activate', () => {
      if (BrowserWindow.getAllWindows().length === 0) createWindow();
    });
  });
}

ipcMain.on('window-minimize', () => {
  if (mainWindow) mainWindow.minimize();
});

ipcMain.on('window-maximize', () => {
  if (mainWindow) {
    if (mainWindow.isMaximized()) mainWindow.unmaximize();
    else mainWindow.maximize();
  }
});

ipcMain.on('window-close', () => {
  if (mainWindow) mainWindow.close();
});

function cleanExit() {
  if (backendProcess) {
    try {
      backendProcess.kill('SIGINT');
    } catch (e) { }
    backendProcess = null;
  }
}

app.on('before-quit', cleanExit);
app.on('will-quit', cleanExit);
app.on('window-all-closed', () => {
  cleanExit();
  if (process.platform !== 'darwin') app.quit();
});
```

### 4.2 التعديل المقترح لملف `frontend/vite.config.ts`
```typescript
import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'
import tailwindcss from '@tailwindcss/vite'

// https://vite.dev/config/
export default defineConfig({
  base: './',
  plugins: [react(), tailwindcss()],
})
```

---

## 5. طريقة التحقق المستقل (Verification Method)

1. **فحص تشغيل الإلكترون بملفات الـ Fallback**:
   - تشغيل التطبيق في بيئة خالية دون تشغيل السيرفر مسبقاً:
     ```powershell
     cd d:\elctercity\desktop
     .\electron-bin\electron.exe .
     ```
   - التحقق من ظهور الواجهة فوراً (0 ثانية شاشة زرقاء) وتحميل ملف `index.html` وأصول الـ CSS/JS.
2. **فحص حوار الأخطاء العربي عند غياب الخادم**:
   - إيقاف خدمة الباك إند عمداً وفحص ظهور رسالة: "Smart Power ERP - تنبيه النظام: تعذر الاتصال بالخادم المحلي للنظام (Port 3000)" وخيارات: `['إعادة المحاولة', 'تشغيل دون اتصال (Offline UI)', 'إغلاق']`.
3. **فحص بناء المثبت الشامل Inno Setup**:
   - التحقق من تجميع المثبت الذاتي الكامل:
     ```powershell
     & "C:\Program Files (x86)\Inno Setup 6\ISCC.exe" "d:\elctercity\SmartPower_Installer.iss"
     ```
   - التأكد من خروج الملف التنفيذي `d:\elctercity\build_installer_output\SmartPower_Station_ERP_Desktop_Setup_v1.0.exe` واحتوائه على كافة الاعتماديات وملفات Prisma و Dist.
