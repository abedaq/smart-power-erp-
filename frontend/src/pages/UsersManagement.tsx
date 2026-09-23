import React, { useState, useMemo } from 'react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { getUsersApi, createUserApi, updateUserApi, resetUserPasswordApi } from '../lib/api';
import { UserCheck, Plus, Key, CheckCircle, XCircle, Gauge, Shield, Users, Edit3, Copy } from 'lucide-react';
import { safeCopyToClipboard } from '../utils/formatters';
import toast from 'react-hot-toast';
import { QUERY_KEYS } from '../constants/queryKeys';

interface UserData {
  id: number;
  username: string;
  full_name: string;
  role: 'ADMIN' | 'CASHIER' | 'COLLECTOR';
  is_active: boolean;
  created_at?: string;
  readings_count?: number;
}

const UsersManagement: React.FC = () => {
  const queryClient = useQueryClient();
  const [showAddModal, setShowAddModal] = useState(false);
  const [showEditModal, setShowEditModal] = useState(false);
  const [showResetModal, setShowResetModal] = useState(false);
  const [selectedUser, setSelectedUser] = useState<UserData | null>(null);
  const [selectedRoleFilter, setSelectedRoleFilter] = useState<'ALL' | 'COLLECTOR' | 'CASHIER' | 'ADMIN'>('ALL');
  const [successPasswordInfo, setSuccessPasswordInfo] = useState<{ username: string; fullName: string; pass: string } | null>(null);

  // Form states
  const [username, setUsername] = useState('');
  const [password, setPassword] = useState('');
  const [fullName, setFullName] = useState('');
  const [role, setRole] = useState<'ADMIN' | 'CASHIER' | 'COLLECTOR'>('COLLECTOR');

  // Reset Password State
  const [newPassword, setNewPassword] = useState('');
  const [editFullName, setEditFullName] = useState('');
  const [editRole, setEditRole] = useState<'ADMIN' | 'CASHIER' | 'COLLECTOR'>('COLLECTOR');

  const { data: users = [], isLoading } = useQuery({
    queryKey: QUERY_KEYS.users,
    queryFn: getUsersApi
  });

  const filteredUsers = useMemo(() => {
    if (selectedRoleFilter === 'ALL') return users;
    return users.filter((u: UserData) => u.role === selectedRoleFilter);
  }, [users, selectedRoleFilter]);

  const createMutation = useMutation({
    mutationFn: createUserApi,
    onSuccess: (res) => {
      if (res.success) {
        toast.success('تم إضافة المستخدم بنجاح');
        setShowAddModal(false);
        setSuccessPasswordInfo({ username, fullName, pass: password });
        resetForm();
        queryClient.invalidateQueries({ queryKey: QUERY_KEYS.users });
      } else {
        toast.error(res.message || 'حدث خطأ أثناء الإضافة');
      }
    },
    onError: (err: any) => {
      toast.error(err.response?.data?.message || 'تعذر إضافة المستخدم');
    }
  });

  const updateMutation = useMutation({
    mutationFn: ({ id, data }: { id: number; data: any }) => updateUserApi(id, data),
    onSuccess: (res) => {
      if (res.success) {
        toast.success('تم تحديث المستخدم بنجاح');
        queryClient.invalidateQueries({ queryKey: QUERY_KEYS.users });
      }
    }
  });

  const resetPasswordMutation = useMutation({
    mutationFn: ({ id, pass }: { id: number; pass: string }) => resetUserPasswordApi(id, pass),
    onSuccess: (res) => {
      if (res.success && selectedUser) {
        toast.success('تم إعادة تعيين كلمة المرور بنجاح');
        setShowResetModal(false);
        setSuccessPasswordInfo({ username: selectedUser.username, fullName: selectedUser.full_name, pass: newPassword });
        setNewPassword('');
        setSelectedUser(null);
      } else {
        toast.error(res.message || 'تعذر تغيير كلمة المرور');
      }
    },
    onError: (err: any) => {
      toast.error(err.response?.data?.message || 'تعذر تغيير كلمة المرور');
    }
  });

  const resetForm = () => {
    setUsername('');
    setPassword('');
    setFullName('');
    setRole('CASHIER');
  };

  const handleCreate = (e: React.FormEvent) => {
    e.preventDefault();
    if (!username || !password || !fullName) {
      toast.error('يرجى إكمال الحقول المطلوبة');
      return;
    }
    createMutation.mutate({ username, password, full_name: fullName, role });
  };

  const handleToggleStatus = (u: UserData) => {
    updateMutation.mutate({
      id: u.id,
      data: { is_active: !u.is_active }
    });
  };

  const openEditModal = (u: UserData) => {
    setSelectedUser(u);
    setEditFullName(u.full_name);
    setEditRole(u.role);
    setShowEditModal(true);
  };

  const handleEditSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    if (!selectedUser || editFullName.trim().length < 3) {
      toast.error('يرجى إدخال اسم كامل من 3 أحرف على الأقل');
      return;
    }
    updateMutation.mutate({
      id: selectedUser.id,
      data: { full_name: editFullName.trim(), role: editRole }
    }, {
      onSuccess: (res) => {
        if (res.success) {
          setShowEditModal(false);
          setSelectedUser(null);
        }
      }
    });
  };

  const handleResetPasswordSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    if (!selectedUser || newPassword.length < 8) {
      toast.error('كلمة المرور يجب أن تكون 8 أحرف على الأقل');
      return;
    }
    resetPasswordMutation.mutate({ id: selectedUser.id, pass: newPassword });
  };

  const getRoleBadge = (userRole: string) => {
    switch (userRole) {
      case 'ADMIN':
        return <span className="bg-purple-100 text-purple-700 border border-purple-200 text-xs px-2.5 py-1 rounded-xl font-bold">مدير نظام</span>;
      case 'CASHIER':
        return <span className="bg-blue-100 text-blue-700 border border-blue-200 text-xs px-2.5 py-1 rounded-xl font-bold">محاسب / أمين صندوق</span>;
      case 'COLLECTOR':
        return <span className="bg-emerald-100 text-emerald-700 border border-emerald-200 text-xs px-2.5 py-1 rounded-xl font-bold">محصل ميداني</span>;
      default:
        return <span className="bg-slate-100 text-slate-700 text-xs px-2.5 py-1 rounded-xl font-bold">{userRole}</span>;
    }
  };

  return (
    <div className="space-y-6" dir="rtl">
      {/* Header */}
      <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-4 bg-white p-5 rounded-2xl border border-slate-200 shadow-sm">
        <div className="flex items-center gap-3">
          <div className="p-3 bg-blue-50 text-blue-600 rounded-xl border border-blue-200">
            <UserCheck size={24} />
          </div>
          <div>
            <h1 className="text-xl font-bold text-slate-900">إدارة المستخدمين والحسابات</h1>
            <p className="text-xs text-slate-500">إضافة المحصلين والمحاسبين وتحديد الصلاحيات والأدوار</p>
          </div>
        </div>

        <button
          onClick={() => setShowAddModal(true)}
          className="flex items-center justify-center gap-2 bg-blue-600 hover:bg-blue-700 text-white px-4 py-2.5 rounded-xl font-bold text-sm shadow-md shadow-blue-500/20 transition-all"
        >
          <Plus size={18} />
          <span>إضافة مستخدم جديد</span>
        </button>
      </div>

      {/* Role Filter Tabs */}
      <div className="flex gap-2 border-b border-slate-200 pb-3 overflow-x-auto">
        <button
          onClick={() => setSelectedRoleFilter('ALL')}
          className={`px-4 py-2 rounded-xl text-xs font-bold transition-all border flex items-center gap-2 ${selectedRoleFilter === 'ALL'
            ? 'bg-blue-600 text-white border-blue-600 shadow-sm'
            : 'bg-white text-slate-600 border-slate-200 hover:bg-slate-50'
            }`}
        >
          <Users size={15} />
          <span>جميع الحسابات ({users.length})</span>
        </button>

        <button
          onClick={() => setSelectedRoleFilter('COLLECTOR')}
          className={`px-4 py-2 rounded-xl text-xs font-bold transition-all border flex items-center gap-2 ${selectedRoleFilter === 'COLLECTOR'
            ? 'bg-emerald-600 text-white border-emerald-600 shadow-sm'
            : 'bg-white text-slate-600 border-slate-200 hover:bg-slate-50'
            }`}
        >
          <Gauge size={15} />
          <span>المحصلين الميدانيين ({users.filter((u: UserData) => u.role === 'COLLECTOR').length})</span>
        </button>

        <button
          onClick={() => setSelectedRoleFilter('CASHIER')}
          className={`px-4 py-2 rounded-xl text-xs font-bold transition-all border flex items-center gap-2 ${selectedRoleFilter === 'CASHIER'
            ? 'bg-blue-600 text-white border-blue-600 shadow-sm'
            : 'bg-white text-slate-600 border-slate-200 hover:bg-slate-50'
            }`}
        >
          <Shield size={15} />
          <span>المحاسبين والكاشير ({users.filter((u: UserData) => u.role === 'CASHIER').length})</span>
        </button>

        <button
          onClick={() => setSelectedRoleFilter('ADMIN')}
          className={`px-4 py-2 rounded-xl text-xs font-bold transition-all border flex items-center gap-2 ${selectedRoleFilter === 'ADMIN'
            ? 'bg-purple-600 text-white border-purple-600 shadow-sm'
            : 'bg-white text-slate-600 border-slate-200 hover:bg-slate-50'
            }`}
        >
          <span>المدراء ({users.filter((u: UserData) => u.role === 'ADMIN').length})</span>
        </button>
      </div>

      {/* Users Table */}
      <div className="bg-white rounded-2xl border border-slate-200 shadow-sm overflow-hidden">
        <div className="overflow-x-auto">
          <table className="w-full text-right border-collapse">
            <thead>
              <tr className="bg-slate-50 border-b border-slate-200 text-slate-600 text-xs font-bold uppercase">
                <th className="p-4">#</th>
                <th className="p-4">اسم المحصل / المستخدم</th>
                <th className="p-4">اسم الدخول (Username)</th>
                <th className="p-4">الدور والصلاحيات</th>
                <th className="p-4">القراءات الميدانية المسجلة</th>
                <th className="p-4">حالة الحساب</th>
                <th className="p-4 text-center">الإجراءات والتحكم</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-slate-100 text-sm">
              {isLoading ? (
                <tr>
                  <td colSpan={7} className="text-center p-8 text-slate-500 font-medium">جاري تحميل حسابات المستخدمين...</td>
                </tr>
              ) : filteredUsers.length === 0 ? (
                <tr>
                  <td colSpan={7} className="text-center p-8 text-slate-500 font-medium">لا يوجد حسابات مسجلة ضمن هذه الفئة.</td>
                </tr>
              ) : (
                filteredUsers.map((u: UserData, index: number) => (
                  <tr key={u.id} className="hover:bg-slate-50/80 transition-colors">
                    <td className="p-4 font-mono font-bold text-slate-400">{index + 1}</td>
                    <td className="p-4 font-bold text-slate-900">{u.full_name}</td>
                    <td className="p-4 font-mono font-bold text-blue-600">@{u.username}</td>
                    <td className="p-4">{getRoleBadge(u.role)}</td>
                    <td className="p-4 font-mono font-bold text-emerald-700">
                      {u.role === 'COLLECTOR' ? `${Number(u.readings_count || 0).toLocaleString('en-US')} قراءة` : '-'}
                    </td>
                    <td className="p-4">
                      {u.is_active ? (
                        <span className="inline-flex items-center gap-1.5 text-emerald-600 bg-emerald-50 border border-emerald-200 text-xs px-2.5 py-1 rounded-xl font-bold">
                          <CheckCircle size={14} /> نشط (مفعل)
                        </span>
                      ) : (
                        <span className="inline-flex items-center gap-1.5 text-rose-600 bg-rose-50 border border-rose-200 text-xs px-2.5 py-1 rounded-xl font-bold">
                          <XCircle size={14} /> مجمد (معطل)
                        </span>
                      )}
                    </td>
                    <td className="p-4">
                      <div className="flex items-center justify-center gap-2">
                        <button
                          onClick={() => openEditModal(u)}
                          title="تعديل الاسم والصلاحية"
                          className="p-2 bg-blue-50 hover:bg-blue-100 text-blue-700 border border-blue-200 rounded-xl text-xs font-bold flex items-center gap-1 transition-all"
                        >
                          <Edit3 size={14} />
                          <span>تعديل</span>
                        </button>

                        <button
                          onClick={() => handleToggleStatus(u)}
                          title={u.is_active ? 'تجميد وتعطيل صلاحيات الدخول' : 'تفعيل الدخول'}
                          className={`p-2 rounded-xl border text-xs font-bold transition-all ${u.is_active
                            ? 'bg-rose-50 text-rose-600 border-rose-200 hover:bg-rose-100'
                            : 'bg-emerald-50 text-emerald-600 border-emerald-200 hover:bg-emerald-100'
                            }`}
                        >
                          {u.is_active ? 'تجميد الحساب' : 'تفعيل الحساب'}
                        </button>

                        <button
                          onClick={() => {
                            setSelectedUser(u);
                            setShowResetModal(true);
                          }}
                          className="p-2 bg-slate-100 hover:bg-slate-200 text-slate-700 border border-slate-200 rounded-xl text-xs font-bold flex items-center gap-1 transition-all"
                        >
                          <Key size={14} />
                          <span>تغيير كلمة المرور</span>
                        </button>
                      </div>
                    </td>
                  </tr>
                ))
              )}
            </tbody>
          </table>
        </div>
      </div>

      {/* Modal Add User */}
      {showAddModal && (
        <div className="fixed inset-0 bg-slate-900/40 backdrop-blur-sm z-50 flex items-center justify-center p-4">
          <div className="bg-white rounded-3xl border border-slate-200 shadow-2xl w-full max-w-md p-6 space-y-5 animate-in fade-in zoom-in-95">
            <h2 className="text-lg font-bold text-slate-900 border-b border-slate-100 pb-3">إضافة مستخدم جديد</h2>

            <form onSubmit={handleCreate} className="space-y-4">
              <div>
                <label className="block text-xs font-bold text-slate-700 mb-1">الاسم الكامل</label>
                <input
                  type="text"
                  value={fullName}
                  onChange={(e) => setFullName(e.target.value)}
                  placeholder="مثال: أحمد عبد الله"
                  className="w-full p-3 bg-slate-50 border border-slate-200 rounded-2xl text-sm font-medium focus:bg-white focus:border-blue-600 outline-none"
                  required
                />
              </div>

              <div>
                <label className="block text-xs font-bold text-slate-700 mb-1">اسم المستخدم</label>
                <input
                  type="text"
                  value={username}
                  onChange={(e) => setUsername(e.target.value)}
                  placeholder="مثال: ahmed_collector"
                  className="w-full p-3 bg-slate-50 border border-slate-200 rounded-2xl text-sm font-medium focus:bg-white focus:border-blue-600 outline-none"
                  required
                />
              </div>

              <div>
                <label className="block text-xs font-bold text-slate-700 mb-1">كلمة المرور</label>
                <input
                  type="password"
                  value={password}
                  onChange={(e) => setPassword(e.target.value)}
                  placeholder="••••••••"
                  className="w-full p-3 bg-slate-50 border border-slate-200 rounded-2xl text-sm font-medium focus:bg-white focus:border-blue-600 outline-none"
                  required
                />
              </div>

              <div>
                <label className="block text-xs font-bold text-slate-700 mb-1">الدور والصلاحيات</label>
                <select
                  value={role}
                  onChange={(e) => setRole(e.target.value as any)}
                  className="w-full p-3 bg-slate-50 border border-slate-200 rounded-2xl text-sm font-medium focus:bg-white focus:border-blue-600 outline-none"
                >
                  <option value="COLLECTOR">محصل ميداني (قراءات وسداد في الميدان)</option>
                  <option value="CASHIER">محاسب / أمين صندوق (فواتير وسداد وتسويات)</option>
                  <option value="ADMIN">مدير المحطة (صلاحية كاملة وإعدادات)</option>
                </select>
              </div>

              <div className="flex items-center gap-3 pt-3">
                <button
                  type="submit"
                  disabled={createMutation.isPending}
                  className="flex-1 py-3 bg-blue-600 hover:bg-blue-700 text-white font-bold text-sm rounded-2xl transition-all shadow-md shadow-blue-500/20"
                >
                  {createMutation.isPending ? 'جاري الإضافة...' : 'إضافة الحساب'}
                </button>
                <button
                  type="button"
                  onClick={() => setShowAddModal(false)}
                  className="py-3 px-5 bg-slate-100 hover:bg-slate-200 text-slate-700 font-bold text-sm rounded-2xl transition-all"
                >
                  إلغاء
                </button>
              </div>
            </form>
          </div>
        </div>
      )}

      {/* Modal Edit User */}
      {showEditModal && selectedUser && (
        <div className="fixed inset-0 bg-slate-900/40 backdrop-blur-sm z-50 flex items-center justify-center p-4">
          <div className="bg-white rounded-3xl border border-slate-200 shadow-2xl w-full max-w-md p-6 space-y-5">
            <h2 className="text-lg font-bold text-slate-900 border-b border-slate-100 pb-3">تعديل بيانات المستخدم</h2>
            <form onSubmit={handleEditSubmit} className="space-y-4">
              <div>
                <label className="block text-xs font-bold text-slate-700 mb-1">الاسم الكامل</label>
                <input
                  type="text"
                  value={editFullName}
                  onChange={(e) => setEditFullName(e.target.value)}
                  className="w-full p-3 bg-slate-50 border border-slate-200 rounded-2xl text-sm font-medium focus:bg-white focus:border-blue-600 outline-none"
                  required
                  minLength={3}
                />
              </div>
              <div>
                <label className="block text-xs font-bold text-slate-700 mb-1">الدور والصلاحيات</label>
                <select
                  value={editRole}
                  onChange={(e) => setEditRole(e.target.value as 'ADMIN' | 'CASHIER' | 'COLLECTOR')}
                  className="w-full p-3 bg-slate-50 border border-slate-200 rounded-2xl text-sm font-medium focus:bg-white focus:border-blue-600 outline-none"
                >
                  <option value="COLLECTOR">محصل ميداني (COLLECTOR)</option>
                  <option value="CASHIER">محاسب / أمين صندوق (CASHIER)</option>
                  <option value="ADMIN">مدير النظام (ADMIN)</option>
                </select>
              </div>
              <div className="flex items-center gap-3 pt-3">
                <button type="submit" disabled={updateMutation.isPending} className="flex-1 py-3 bg-blue-600 hover:bg-blue-700 text-white font-bold text-sm rounded-2xl transition-all">
                  {updateMutation.isPending ? 'جاري الحفظ...' : 'حفظ التعديل'}
                </button>
                <button type="button" onClick={() => setShowEditModal(false)} className="py-3 px-5 bg-slate-100 hover:bg-slate-200 text-slate-700 font-bold text-sm rounded-2xl transition-all">
                  إلغاء
                </button>
              </div>
            </form>
          </div>
        </div>
      )}

      {/* Modal Reset Password */}
      {showResetModal && selectedUser && (
        <div className="fixed inset-0 bg-slate-900/40 backdrop-blur-sm z-50 flex items-center justify-center p-4">
          <div className="bg-white rounded-3xl border border-slate-200 shadow-2xl w-full max-w-md p-6 space-y-5">
            <h2 className="text-lg font-bold text-slate-900 border-b border-slate-100 pb-3">
              تغيير كلمة المرور للمستخدم: <span className="text-blue-600">{selectedUser.full_name}</span>
            </h2>

            <form onSubmit={handleResetPasswordSubmit} className="space-y-4">
              <div>
                <label className="block text-xs font-bold text-slate-700 mb-1">كلمة المرور الجديدة</label>
                <input
                  type="password"
                  value={newPassword}
                  onChange={(e) => setNewPassword(e.target.value)}
                  placeholder="أدخل كلمة المرور الجديدة"
                  className="w-full p-3 bg-slate-50 border border-slate-200 rounded-2xl text-sm font-medium focus:bg-white focus:border-blue-600 outline-none"
                  minLength={8}
                  required
                />
              </div>

              <div className="flex items-center gap-3 pt-3">
                <button
                  type="submit"
                  disabled={resetPasswordMutation.isPending}
                  className="flex-1 py-3 bg-blue-600 hover:bg-blue-700 text-white font-bold text-sm rounded-2xl transition-all shadow-md shadow-blue-500/20"
                >
                  {resetPasswordMutation.isPending ? 'جاري الحفظ...' : 'حفظ كلمة المرور'}
                </button>
                <button
                  type="button"
                  onClick={() => setShowResetModal(false)}
                  className="py-3 px-5 bg-slate-100 hover:bg-slate-200 text-slate-700 font-bold text-sm rounded-2xl transition-all"
                >
                  إلغاء
                </button>
              </div>
            </form>
          </div>
        </div>
      )}

      {/* Modal Credentials Success */}
      {successPasswordInfo && (
        <div className="fixed inset-0 bg-slate-900/40 backdrop-blur-sm z-50 flex items-center justify-center p-4">
          <div className="bg-white rounded-3xl border border-slate-200 shadow-2xl w-full max-w-md p-6 space-y-5">
            <div className="flex items-center gap-3 text-emerald-600 border-b border-slate-100 pb-3">
              <CheckCircle size={24} />
              <h2 className="text-lg font-bold text-slate-900">تم اعتماد بيانات الدخول بنجاح</h2>
            </div>
            <p className="text-xs text-slate-600 font-medium">يمكنك نسخ بيانات كلمة المرور الجديدة أدناه وتسليمها للمستخدم:</p>

            <div className="space-y-3 bg-slate-50 p-4 rounded-2xl border border-slate-200">
              <div>
                <span className="text-xs text-slate-500 font-bold block">المستخدم:</span>
                <span className="text-sm font-bold text-slate-900">{successPasswordInfo.fullName} (@{successPasswordInfo.username})</span>
              </div>
              <div>
                <span className="text-xs text-slate-500 font-bold block">كلمة المرور الجديدة:</span>
                <div className="flex items-center justify-between gap-2 mt-1">
                  <span className="font-mono font-bold text-blue-600 bg-white px-3 py-1.5 rounded-xl border border-slate-200 text-base select-all">
                    {successPasswordInfo.pass}
                  </span>
                  <button
                    onClick={async () => {
                      const ok = await safeCopyToClipboard(`اسم الدخول: ${successPasswordInfo.username}\nكلمة المرور: ${successPasswordInfo.pass}`);
                      if (ok) {
                        toast.success('تم نسخ بيانات الدخول للذاكرة');
                      } else {
                        toast.error('فشل نسخ بيانات الدخول');
                      }
                    }}
                    className="p-2 bg-blue-600 hover:bg-blue-700 text-white rounded-xl text-xs font-bold flex items-center gap-1 transition-all"
                  >
                    <Copy size={16} />
                    <span>نسخ</span>
                  </button>
                </div>
              </div>
            </div>

            <div className="pt-2">
              <button
                onClick={() => setSuccessPasswordInfo(null)}
                className="w-full py-3 bg-slate-900 hover:bg-slate-800 text-white font-bold text-sm rounded-2xl transition-all"
              >
                إغلاق
              </button>
            </div>
          </div>
        </div>
      )}

    </div>
  );
};

export default UsersManagement;
