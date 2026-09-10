import React from 'react';

interface StationLogoProps {
  className?: string;
  size?: number;
}

export const StationLogo: React.FC<StationLogoProps> = ({ className = '', size = 56 }) => {
  return (
    <img
      src="/station_logo.png"
      alt="شعار محطة الضياء لتوليد الطاقة الكهربائية"
      style={{ width: `${size}px`, height: `${size}px` }}
      className={`inline-block shrink-0 object-contain ${className}`}
    />
  );
};
