import React, { useState } from 'react';
import { Percent, ChevronDown, ChevronUp } from 'lucide-react';

interface RouteProgressWidgetProps {
  progressData: Array<{
    route: string;
    total: number;
    read: number;
    percentage: number;
  }>;
}

export const RouteProgressWidget: React.FC<RouteProgressWidgetProps> = ({ progressData = [] }) => {
  const [isExpanded, setIsExpanded] = useState(false);

  const totalCustomers = progressData.reduce((acc, p) => acc + p.total, 0);
  const totalRead = progressData.reduce((acc, p) => acc + p.read, 0);
  const overallPercentage = totalCustomers > 0 ? Math.round((totalRead / totalCustomers) * 100) : 0;

  return (
    <div className="bg-slate-900/70 border border-slate-800 rounded-2xl p-4 backdrop-blur-md shadow-xl transition-all">
      <div className="flex justify-between items-center">
        <div className="flex items-center gap-3">
          <div className="p-2 bg-blue-500/10 text-blue-400 rounded-xl border border-blue-500/20">
            <Percent size={18} />
          </div>
          <div>
            <div className="flex items-center gap-2">
              <h3 className="font-bold text-white text-sm">مؤشر إنجاز القراءة الكلي:</h3>
              <span className="text-blue-400 font-bold font-mono text-sm">{overallPercentage}%</span>
              <span className="text-slate-400 text-xs font-medium">({totalRead} من {totalCustomers} مشترك)</span>
            </div>
            {/* Main compact bar */}
            <div className="w-48 sm:w-64 bg-slate-800 h-2 rounded-full overflow-hidden mt-1.5 border border-slate-700/50">
              <div 
                className="bg-linear-to-r from-blue-500 to-emerald-400 h-full rounded-full transition-all duration-500" 
                style={{ width: `${overallPercentage}%` }}
              />
            </div>
          </div>
        </div>

        <button 
          onClick={() => setIsExpanded(!isExpanded)}
          className="bg-slate-800/80 hover:bg-slate-700/80 text-slate-300 border border-slate-700 px-3 py-1.5 rounded-xl text-xs font-semibold flex items-center gap-1.5 transition-colors"
        >
          <span>{isExpanded ? 'إخفاء التفاصيل' : 'تفاصيل خطوط السير'}</span>
          {isExpanded ? <ChevronUp size={14} /> : <ChevronDown size={14} />}
        </button>
      </div>

      {isExpanded && (
        <div className="mt-4 pt-4 border-t border-slate-800/80 grid grid-cols-1 sm:grid-cols-2 md:grid-cols-3 lg:grid-cols-4 gap-3">
          {progressData.map((p, idx) => (
            <div key={idx} className="bg-slate-950/60 p-3 rounded-xl border border-slate-800/80 space-y-1.5">
              <div className="flex justify-between text-xs font-semibold">
                <span className="text-slate-200">{p.route}</span>
                <span className="text-blue-400 font-mono">{p.percentage}%</span>
              </div>
              <div className="w-full bg-slate-800 h-1.5 rounded-full overflow-hidden">
                <div 
                  className={`h-full rounded-full transition-all ${
                    p.percentage >= 90 ? 'bg-emerald-500' :
                    p.percentage >= 50 ? 'bg-blue-500' :
                    'bg-amber-500'
                  }`}
                  style={{ width: `${p.percentage}%` }}
                />
              </div>
              <div className="text-[10px] text-slate-400">
                {p.read} من {p.total} مشترك
              </div>
            </div>
          ))}
          {progressData.length === 0 && (
            <div className="col-span-full text-center text-slate-500 text-xs py-2">
              لا توجد بيانات لخطوط السير حالياً.
            </div>
          )}
        </div>
      )}
    </div>
  );
};
