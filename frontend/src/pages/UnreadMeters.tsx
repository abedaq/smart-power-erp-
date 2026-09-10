import React from 'react';
import { Navigate } from 'react-router-dom';

const UnreadMeters: React.FC = () => {
  return <Navigate to="/invoices" replace />;
};

export default UnreadMeters;


