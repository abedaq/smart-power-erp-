import React, { useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { useAuth } from '../context/AuthContext';
import { Zap, Lock, User, AlertCircle, ArrowLeft } from 'lucide-react';
import toast from 'react-hot-toast';

const Login: React.FC = () => {
  const [username, setUsername] = useState('');
  const [password, setPassword] = useState('');
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [errorMsg, setErrorMsg] = useState('');
  const [rememberMe, setRememberMe] = useState(true);

  const { login } = useAuth();
  const navigate = useNavigate();

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!username || !password) {
      setErrorMsg('يرجى إدخال اسم المستخدم وكلمة المرور');
      return;
    }

    try {
      setIsSubmitting(true);
      setErrorMsg('');
      await login(username, password, rememberMe);
      toast.success('تم تسجيل الدخول بنجاح ⚡');
      navigate('/');
    } catch (err: any) {
      setErrorMsg(err.message || 'اسم المستخدم أو كلمة المرور غير صحيحة');
    } finally {
      setIsSubmitting(false);
    }
  };

  return (
    <div className="min-h-screen bg-slate-50 flex items-center justify-center p-4 relative" dir="rtl">
      <div className="w-full max-w-md bg-white rounded-3xl border border-slate-200 shadow-xl shadow-slate-200/50 p-8 space-y-6">
        
        {/* Header Branding */}
        <div className="text-center space-y-3">
          <div className="w-14 h-14 bg-gradient-to-tr from-blue-600 to-indigo-600 rounded-2xl flex items-center justify-center text-white mx-auto shadow-lg shadow-blue-500/30 animate-pulse">
            <Zap size={32} />
          </div>
          <div>
            <h1 className="text-2xl font-black text-slate-900 tracking-tight">Smart Power ERP</h1>
            <p className="text-sm font-medium text-slate-500 mt-1">نظام إدارة الكهرباء والتحصيل الذكي</p>
          </div>
        </div>

        {/* Error Alert */}
        {errorMsg && (
          <div className="bg-rose-50 border border-rose-200 text-rose-700 px-4 py-3 rounded-2xl space-y-2 text-xs font-semibold animate-shake">
            <div className="flex items-center gap-2">
              <AlertCircle size={18} className="shrink-0" />
              <span className="leading-relaxed">{errorMsg}</span>
            </div>
          </div>
        )}

        {/* Form */}
        <form onSubmit={handleSubmit} className="space-y-4">
          <div>
            <label htmlFor="username-input" className="block text-xs font-bold text-slate-700 mb-1.5">اسم المستخدم</label>
            <div className="relative">
              <input
                id="username-input"
                type="text"
                value={username}
                onChange={(e) => setUsername(e.target.value)}
                placeholder="أدخل اسم المستخدم"
                className="w-full pl-4 pr-10 py-3 bg-slate-50 border border-slate-200 rounded-2xl text-slate-900 text-sm font-medium focus:bg-white focus:border-blue-600 focus:ring-4 focus:ring-blue-500/10 transition-all outline-none"
                required
              />
              <User size={18} className="absolute right-3.5 top-3.5 text-slate-400" />
            </div>
          </div>

          <div>
            <label htmlFor="password-input" className="block text-xs font-bold text-slate-700 mb-1.5">كلمة المرور</label>
            <div className="relative">
              <input
                id="password-input"
                type="password"
                value={password}
                onChange={(e) => setPassword(e.target.value)}
                placeholder="••••••••"
                className="w-full pl-4 pr-10 py-3 bg-slate-50 border border-slate-200 rounded-2xl text-slate-900 text-sm font-medium focus:bg-white focus:border-blue-600 focus:ring-4 focus:ring-blue-500/10 transition-all outline-none"
                required
              />
              <Lock size={18} className="absolute right-3.5 top-3.5 text-slate-400" />
            </div>
          </div>

          {/* Remember Me Checkbox */}
          <div className="flex items-center justify-between pt-1">
            <label className="flex items-center gap-2 cursor-pointer text-xs font-bold text-slate-700 select-none">
              <input
                type="checkbox"
                checked={rememberMe}
                onChange={(e) => setRememberMe(e.target.checked)}
                className="w-4 h-4 text-blue-600 border-slate-300 rounded focus:ring-blue-500 cursor-pointer"
              />
              <span>تذكرني وحفظ الجلسة دائمًا 📱</span>
            </label>
          </div>

          <button
            type="submit"
            disabled={isSubmitting}
            className="w-full py-3.5 px-6 bg-gradient-to-r from-blue-600 to-indigo-600 hover:from-blue-700 hover:to-indigo-700 text-white font-bold text-sm rounded-2xl shadow-lg shadow-blue-600/25 transition-all flex items-center justify-center gap-2 group disabled:opacity-50"
          >
            {isSubmitting ? (
              <span>جاري تسجيل الدخول...</span>
            ) : (
              <>
                <span>تسجيل الدخول</span>
                <ArrowLeft size={18} className="group-hover:-translate-x-1 transition-transform" />
              </>
            )}
          </button>
        </form>

      </div>
    </div>
  );
};

export default Login;

