import React, { useState, useEffect } from 'react';
import { X, UserPlus, Phone, MapPin, Gauge, Calendar, Hash } from 'lucide-react';
import { createCustomer, getNextSubscriberNumber } from '../services/customer.service';
import { toEnglishDigits, sanitizeDecimalInput } from '../utils/formatters';
import toast from 'react-hot-toast';

interface AddCustomerModalProps {
  isOpen: boolean;
  onClose: () => void;
  onCustomerAdded?: () => void;
  currentCycle?: string;
}

export const AddCustomerModal: React.FC<AddCustomerModalProps> = ({
  isOpen,
  onClose,
  onCustomerAdded,
  currentCycle,
}) => {
  const [fullName, setFullName] = useState('');
  const [subscriberNumber, setSubscriberNumber] = useState('');
  const [phoneNumber, setPhoneNumber] = useState('');
  const [meterNumber, setMeterNumber] = useState('');
  const [routeNumber, setRouteNumber] = useState('1');
  const [address, setAddress] = useState('');
  const [startCycle, setStartCycle] = useState(
    currentCycle && currentCycle !== 'all' ? currentCycle : 'أغسطس 1'
  );
  const [initialReading, setInitialReading] = useState('');
  const [arrears, setArrears] = useState('');
  const [isSubmitting, setIsSubmitting] = useState(false);

  useEffect(() => {
    if (isOpen) {
      if (currentCycle && currentCycle !== 'all') {
        setStartCycle(currentCycle);
      }
      getNextSubscriberNumber().then((nextNum) => {
        setSubscriberNumber(nextNum);
      });
    }
  }, [currentCycle, isOpen]);

  if (!isOpen) return null;

  const handlePhoneChange = (val: string) => {
    const clean = toEnglishDigits(val).replace(/\D/g, '');
    setPhoneNumber(clean);
  };

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();

    const cleanName = fullName.trim();
    if (!cleanName) {
      toast.error('يرجى إدخال اسم المشترك');
      return;
    }

    let cleanPhone = toEnglishDigits(phoneNumber).replace(/\D/g, '');
    if (cleanPhone.startsWith('967')) {
      cleanPhone = cleanPhone.slice(3);
    }
    if (cleanPhone.startsWith('0')) {
      cleanPhone = cleanPhone.slice(1);
    }

    if (cleanPhone.length !== 9 || !cleanPhone.startsWith('7')) {
      toast.error('يرجى إدخال رقم هاتف يمني صحيح مكون من 9 أرقام يبدأ بـ 7 (مثال: 734019059)');
      return;
    }

    const initReadingNum = Number(toEnglishDigits(initialReading)) || 0;
    const arrearsNum = Number(toEnglishDigits(arrears)) || 0;

    setIsSubmitting(true);
    try {
      await createCustomer({
        full_name: cleanName,
        subscriber_number: subscriberNumber.trim() || undefined,
        phone_number: cleanPhone,
        meter_number: meterNumber.trim() || undefined,
        route_number: routeNumber.trim() || '1',
        address: address.trim() || undefined,
        initial_reading: initReadingNum,
        start_cycle: startCycle,
        arrears: arrearsNum,
        status: 'Active',
      });

      toast.success(`تمت إضافة المشترك [${cleanName}] بنجاح برقم حساب [${subscriberNumber.trim()}] وإدراجه في دورة [${startCycle}] وما بعدها`);
      
      // Reset form
      setFullName('');
      setSubscriberNumber('');
      setPhoneNumber('');
      setMeterNumber('');
      setRouteNumber('1');
      setAddress('');
      setInitialReading('');
      setArrears('');

      if (onCustomerAdded) {
        onCustomerAdded();
      }
      onClose();
    } catch (err: any) {
      toast.error(`فشل إضافة المشترك: ${err.response?.data?.message || err.message}`);
    } finally {
      setIsSubmitting(false);
    }
  };

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-slate-900/50 backdrop-blur-xs p-4 overflow-y-auto" dir="rtl">
      <div className="bg-white rounded-2xl shadow-2xl border border-slate-200 w-full max-w-lg overflow-hidden animate-in fade-in zoom-in-95 duration-200 my-8">
        {/* Header */}
        <div className="bg-slate-900 text-white p-4 sm:p-5 flex items-center justify-between border-b border-slate-800">
          <div className="flex items-center gap-2.5">
            <div className="w-10 h-10 rounded-xl bg-blue-600/30 border border-blue-500/40 flex items-center justify-center text-blue-400">
              <UserPlus size={20} />
            </div>
            <div>
              <h2 className="text-base sm:text-lg font-black text-white">إضافة مشترك جديد</h2>
              <p className="text-xs text-slate-400">تسجيل مشترك وتوليد حسابه المالي فوراً بدءاً من الدورة المحددة</p>
            </div>
          </div>
          <button
            onClick={onClose}
            type="button"
            className="p-1.5 text-slate-400 hover:text-white rounded-lg hover:bg-slate-800 transition-colors"
          >
            <X size={20} />
          </button>
        </div>

        {/* Form Body */}
        <form onSubmit={handleSubmit} className="p-5 space-y-4">
          {/* Full Name & Subscriber Number Grid */}
          <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
            <div>
              <label className="block text-xs font-bold text-slate-700 mb-1">
                الاسم الكامل للمشترك <span className="text-rose-500">*</span>
              </label>
              <input
                type="text"
                required
                value={fullName}
                onChange={(e) => setFullName(e.target.value)}
                placeholder="مثال: ماجد فرحان القدسي"
                className="w-full px-3.5 py-2.5 bg-slate-50 border border-slate-300 rounded-xl text-slate-900 text-sm focus:outline-none focus:border-blue-600 focus:bg-white font-medium"
              />
            </div>

            <div>
              <label className="block text-xs font-bold text-slate-700 mb-1">
                رقم المشترك / الحساب <span className="text-rose-500">*</span>
              </label>
              <div className="relative">
                <input
                  type="text"
                  required
                  value={subscriberNumber}
                  onChange={(e) => setSubscriberNumber(toEnglishDigits(e.target.value))}
                  placeholder="مثال: 10016"
                  className="w-full px-3.5 py-2.5 bg-blue-50/60 border border-blue-200 rounded-xl text-blue-950 text-sm focus:outline-none focus:border-blue-600 focus:bg-white font-mono font-bold tracking-wider pl-9"
                />
                <Hash size={16} className="absolute left-3 top-3 text-blue-500 pointer-events-none" />
              </div>
              <p className="text-[10px] text-blue-600 mt-0.5 font-medium">رقم تسلسلي مقترح تلقائياً (قابل للتعديل)</p>
            </div>
          </div>

          {/* Start Cycle Selector */}
          <div>
            <label className="block text-xs font-bold text-slate-700 mb-1">
              دورة بدء الاشتراك (الدورة التي ينضم فيها المشترك) <span className="text-rose-500">*</span>
            </label>
            <div className="relative">
              <select
                value={startCycle}
                onChange={(e) => setStartCycle(e.target.value)}
                className="w-full px-3.5 py-2.5 bg-slate-50 border border-slate-300 rounded-xl text-slate-900 text-sm focus:outline-none focus:border-blue-600 focus:bg-white font-bold pl-9 cursor-pointer"
              >
                <optgroup label="عام 2026">
                  <option value="أغسطس 1">أغسطس 1</option>
                  <option value="أغسطس 2">أغسطس 2</option>
                  <option value="سبتمبر 1">سبتمبر 1</option>
                  <option value="سبتمبر 2">سبتمبر 2</option>
                  <option value="أكتوبر 1">أكتوبر 1</option>
                  <option value="أكتوبر 2">أكتوبر 2</option>
                  <option value="نوفمبر 1">نوفمبر 1</option>
                  <option value="نوفمبر 2">نوفمبر 2</option>
                  <option value="ديسمبر 1">ديسمبر 1</option>
                  <option value="ديسمبر 2">ديسمبر 2</option>
                </optgroup>
                <optgroup label="عام 2027">
                  <option value="يناير 1 - 2027">يناير 1 - 2027</option>
                  <option value="يناير 2 - 2027">يناير 2 - 2027</option>
                  <option value="فبراير 1 - 2027">فبراير 1 - 2027</option>
                  <option value="فبراير 2 - 2027">فبراير 2 - 2027</option>
                  <option value="مارس 1 - 2027">مارس 1 - 2027</option>
                  <option value="مارس 2 - 2027">مارس 2 - 2027</option>
                  <option value="أبريل 1 - 2027">أبريل 1 - 2027</option>
                  <option value="أبريل 2 - 2027">أبريل 2 - 2027</option>
                  <option value="مايو 1 - 2027">مايو 1 - 2027</option>
                  <option value="مايو 2 - 2027">مايو 2 - 2027</option>
                  <option value="يونيو 1 - 2027">يونيو 1 - 2027</option>
                  <option value="يونيو 2 - 2027">يونيو 2 - 2027</option>
                  <option value="يوليو 1 - 2027">يوليو 1 - 2027</option>
                  <option value="يوليو 2 - 2027">يوليو 2 - 2027</option>
                  <option value="أغسطس 1 - 2027">أغسطس 1 - 2027</option>
                  <option value="أغسطس 2 - 2027">أغسطس 2 - 2027</option>
                  <option value="سبتمبر 1 - 2027">سبتمبر 1 - 2027</option>
                  <option value="سبتمبر 2 - 2027">سبتمبر 2 - 2027</option>
                  <option value="أكتوبر 1 - 2027">أكتوبر 1 - 2027</option>
                  <option value="أكتوبر 2 - 2027">أكتوبر 2 - 2027</option>
                  <option value="نوفمبر 1 - 2027">نوفمبر 1 - 2027</option>
                  <option value="نوفمبر 2 - 2027">نوفمبر 2 - 2027</option>
                  <option value="ديسمبر 1 - 2027">ديسمبر 1 - 2027</option>
                  <option value="ديسمبر 2 - 2027">ديسمبر 2 - 2027</option>
                </optgroup>
                <optgroup label="عام 2028">
                  <option value="يناير 1 - 2028">يناير 1 - 2028</option>
                  <option value="يناير 2 - 2028">يناير 2 - 2028</option>
                </optgroup>
              </select>
              <Calendar size={16} className="absolute left-3 top-3 text-slate-400 pointer-events-none" />
            </div>
            <p className="text-[11px] text-slate-500 mt-1 font-medium">
              لن يظهر المشترك في الدورات السابقة لدورة انضمامه، وسيبدأ ظهور فواتيره وحساباته بدءاً من هذه الدورة وما يليها.
            </p>
          </div>

          {/* Phone Number & Meter Number Grid */}
          <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
            <div>
              <label className="block text-xs font-bold text-slate-700 mb-1">
                رقم الهاتف (9 أرقام) <span className="text-rose-500">*</span>
              </label>
              <div className="relative">
                <input
                  type="text"
                  required
                  value={phoneNumber}
                  onChange={(e) => handlePhoneChange(e.target.value)}
                  placeholder="734019059"
                  maxLength={12}
                  className="w-full px-3.5 py-2.5 bg-slate-50 border border-slate-300 rounded-xl text-slate-900 text-sm focus:outline-none focus:border-blue-600 focus:bg-white font-mono font-bold pl-9 text-left"
                  dir="ltr"
                />
                <Phone size={16} className="absolute left-3 top-3 text-slate-400 pointer-events-none" />
              </div>
            </div>

            <div>
              <label className="block text-xs font-bold text-slate-700 mb-1">
                رقم العداد
              </label>
              <div className="relative">
                <input
                  type="text"
                  value={meterNumber}
                  onChange={(e) => setMeterNumber(toEnglishDigits(e.target.value))}
                  placeholder="MTR-10025"
                  className="w-full px-3.5 py-2.5 bg-slate-50 border border-slate-300 rounded-xl text-slate-900 text-sm focus:outline-none focus:border-blue-600 focus:bg-white font-mono font-bold"
                />
                <Gauge size={16} className="absolute left-3 top-3 text-slate-400 pointer-events-none" />
              </div>
            </div>
          </div>

          {/* Route Number & Region/Address */}
          <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
            <div>
              <label className="block text-xs font-bold text-slate-700 mb-1">
                خط السير (Route) <span className="text-rose-500">*</span>
              </label>
              <input
                type="text"
                required
                value={routeNumber}
                onChange={(e) => setRouteNumber(toEnglishDigits(e.target.value))}
                placeholder="1"
                className="w-full px-3.5 py-2.5 bg-slate-50 border border-slate-300 rounded-xl text-slate-900 text-sm focus:outline-none focus:border-blue-600 focus:bg-white font-mono font-bold"
              />
            </div>

            <div>
              <label className="block text-xs font-bold text-slate-700 mb-1">
                المنطقة / الحي / العنوان
              </label>
              <div className="relative">
                <input
                  type="text"
                  value={address}
                  onChange={(e) => setAddress(e.target.value)}
                  placeholder="شارع تعز - بير باشا"
                  className="w-full px-3.5 py-2.5 bg-slate-50 border border-slate-300 rounded-xl text-slate-900 text-sm focus:outline-none focus:border-blue-600 focus:bg-white font-medium"
                />
                <MapPin size={16} className="absolute left-3 top-3 text-slate-400 pointer-events-none" />
              </div>
            </div>
          </div>

          {/* Initial Reading & Arrears */}
          <div className="grid grid-cols-1 sm:grid-cols-2 gap-3 p-3 bg-slate-50 border border-slate-200 rounded-xl">
            <div>
              <label className="block text-xs font-bold text-slate-700 mb-1">
                القراءة السابقة / الابتدائية (كيلو)
              </label>
              <input
                type="text"
                value={initialReading}
                onChange={(e) => setInitialReading(sanitizeDecimalInput(e.target.value))}
                placeholder="0"
                className="w-full px-3 py-2 bg-white border border-slate-300 rounded-lg text-slate-900 text-sm focus:outline-none focus:border-blue-600 font-mono font-bold text-left"
                dir="ltr"
              />
            </div>

            <div>
              <label className="block text-xs font-bold text-slate-700 mb-1">
                المتأخرات السابقة (ر.ي)
              </label>
              <input
                type="text"
                value={arrears}
                onChange={(e) => setArrears(sanitizeDecimalInput(e.target.value))}
                placeholder="0"
                className="w-full px-3 py-2 bg-white border border-slate-300 rounded-lg text-slate-900 text-sm focus:outline-none focus:border-blue-600 font-mono font-bold text-left text-amber-700"
                dir="ltr"
              />
            </div>
          </div>

          {/* Footer Actions */}
          <div className="flex items-center justify-end gap-2.5 pt-3 border-t border-slate-200">
            <button
              type="button"
              onClick={onClose}
              className="px-4 py-2.5 rounded-xl border border-slate-300 text-slate-700 text-xs font-bold hover:bg-slate-100 transition-colors"
            >
              إلغاء
            </button>
            <button
              type="submit"
              disabled={isSubmitting}
              className="px-6 py-2.5 rounded-xl bg-blue-600 hover:bg-blue-700 text-white text-xs font-black shadow-md shadow-blue-500/25 transition-all flex items-center gap-1.5 disabled:opacity-50"
            >
              {isSubmitting ? (
                <span>جاري الحفظ...</span>
              ) : (
                <>
                  <UserPlus size={16} />
                  <span>حفظ وإضافة إلى الكشف</span>
                </>
              )}
            </button>
          </div>
        </form>
      </div>
    </div>
  );
};
