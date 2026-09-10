import React, { useState, useEffect } from 'react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { getSettings, updateSettings } from '../services/settings.service';
import { sanitizeDecimalInput } from '../utils/formatters';

interface ArrearsThresholdModalProps {
  onClose: () => void;
}

export const ArrearsThresholdModal: React.FC<ArrearsThresholdModalProps> = ({ onClose }) => {
  const queryClient = useQueryClient();
  const [threshold, setThreshold] = useState('0');

  const { data: settings, isLoading } = useQuery({
    queryKey: ['settings'],
    queryFn: getSettings
  });

  useEffect(() => {
    if (settings) setThreshold(settings.arrears_threshold?.toString() || '0');
  }, [settings]);

  const mutation = useMutation({
    mutationFn: updateSettings,
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['settings'] });
      onClose();
    }
  });

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    mutation.mutate({ arrears_threshold: parseFloat(threshold) || 0 });
  };

  return (
    <div className="fixed inset-0 bg-black/50 flex items-center justify-center z-50">
      <div className="bg-gray-800 p-6 rounded-2xl w-full max-w-md border border-gray-700 shadow-2xl">
        <h2 className="text-xl font-bold mb-2">إعدادات حد المديونية</h2>
        <p className="text-sm text-gray-400 mb-6">قم بتحديد الحد الأقصى المسموح للمديونية، سيتم تمييز العملاء المتجاوزين باللون الأحمر.</p>
        
        {isLoading ? (
          <div className="text-center text-gray-500 py-4">جاري التحميل...</div>
        ) : (
          <form onSubmit={handleSubmit} className="space-y-4">
            <div>
              <label className="block text-gray-400 mb-2 font-medium">الحد الأقصى للمديونية (ر.ي)</label>
              <div className="relative">
                <input 
                  type="text" 
                  inputMode="decimal"
                  value={threshold} 
                  onChange={e => setThreshold(sanitizeDecimalInput(e.target.value))} 
                  className="w-full bg-gray-900 border border-gray-700 rounded-xl px-4 py-3 text-white pl-12 focus:border-blue-500 focus:ring-1 focus:ring-blue-500 outline-none transition-all font-mono" 
                />
                <span className="absolute left-4 top-1/2 -translate-y-1/2 text-gray-500 font-bold">YR</span>
              </div>
            </div>
            
            <div className="flex justify-end gap-3 mt-8">
              <button 
                type="button" 
                onClick={onClose} 
                className="px-6 py-2 text-gray-400 hover:text-white transition-colors"
              >
                إلغاء
              </button>
              <button 
                type="submit" 
                disabled={mutation.isPending} 
                className="bg-blue-600 hover:bg-blue-700 text-white px-6 py-2 rounded-xl font-medium transition-all shadow-lg hover:shadow-blue-500/20"
              >
                {mutation.isPending ? 'جاري الحفظ...' : 'حفظ الإعدادات'}
              </button>
            </div>
          </form>
        )}
      </div>
    </div>
  );
};
