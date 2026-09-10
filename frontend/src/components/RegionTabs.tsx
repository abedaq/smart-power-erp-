import React from 'react';

interface RegionTabsProps {
  regions: string[];
  selectedRegion: string;
  onSelectRegion: (region: string) => void;
}

export const RegionTabs: React.FC<RegionTabsProps> = ({
  regions,
  selectedRegion,
  onSelectRegion,
}) => {
  return (
    <div className="flex overflow-x-auto gap-2 pb-2 mb-4 [&::-webkit-scrollbar]:hidden [-ms-overflow-style:none] scrollbar-none">
      <button
        onClick={() => onSelectRegion('all')}
        className={`px-4 py-2 rounded-xl text-xs font-semibold whitespace-nowrap transition-all duration-200 border ${
          selectedRegion === 'all'
            ? 'bg-blue-600/90 text-white border-blue-500 shadow-lg shadow-blue-500/20 backdrop-blur-md'
            : 'bg-slate-900/60 text-slate-400 border-slate-800 hover:text-white hover:bg-slate-800/60 backdrop-blur-md'
        }`}
      >
        كل المناطق
      </button>
      {regions.map((r: string) => (
        <button
          key={r}
          onClick={() => onSelectRegion(r)}
          className={`px-4 py-2 rounded-xl text-xs font-semibold whitespace-nowrap transition-all duration-200 border ${
            selectedRegion === r
              ? 'bg-blue-600/90 text-white border-blue-500 shadow-lg shadow-blue-500/20 backdrop-blur-md'
              : 'bg-slate-900/60 text-slate-400 border-slate-800 hover:text-white hover:bg-slate-800/60 backdrop-blur-md'
          }`}
        >
          {r}
        </button>
      ))}
    </div>
  );
};
