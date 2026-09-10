import React, { createContext, useContext, useState, useEffect } from 'react';
import api, { loginApi } from '../lib/api';
import type { User } from '../types';

interface AuthContextType {
  user: User | null;
  token: string | null;
  isLoading: boolean;
  login: (username: string, password: string, rememberMe?: boolean) => Promise<void>;
  logout: () => void;
}

const AuthContext = createContext<AuthContextType | undefined>(undefined);

export const AuthProvider: React.FC<{ children: React.ReactNode }> = ({ children }) => {
  const [user, setUser] = useState<User | null>(() => {
    const savedUser = localStorage.getItem('user');
    return savedUser ? JSON.parse(savedUser) : null;
  });
  const [token, setToken] = useState<string | null>(() => localStorage.getItem('token'));
  const [isLoading, setIsLoading] = useState(true);

  useEffect(() => {
    const initAuth = async () => {
      const storedToken = localStorage.getItem('token');
      if (storedToken) {
        try {
          const res = await api.get('/auth/me');
          if (res.data?.success && (res.data.user || res.data.data)) {
            const userData = res.data.user || res.data.data;
            const userObj: User = {
              id: userData.id,
              username: userData.username,
              full_name: userData.full_name,
              role: userData.role,
              is_active: userData.is_active ?? true,
            };
            setUser(userObj);
            setToken(storedToken);
            localStorage.setItem('user', JSON.stringify(userObj));
          }
        } catch (e: any) {
          if (e?.response?.status === 401) {
            console.warn('Session expired on backend, clearing credentials.');
            localStorage.removeItem('token');
            localStorage.removeItem('user');
            setToken(null);
            setUser(null);
          } else {
            // Keep existing offline session if server is starting or network glitch
            console.log('Backend check temporary error, preserving session credentials.');
          }
        }
      }
      setIsLoading(false);
    };

    initAuth();
  }, []);

  const login = async (username: string, password: string, rememberMe: boolean = true) => {
    const cleanUsername = username.trim();

    // 1. Authenticate with Standalone Go Backend API
    try {
      const res = await loginApi({ username: cleanUsername, password });
      if (res.success && res.token && (res.user || res.data)) {
        const userData = res.user || res.data;
        const userObj: User = {
          id: userData.id,
          username: userData.username,
          full_name: userData.full_name,
          role: userData.role,
          is_active: true,
        };
        setToken(res.token);
        setUser(userObj);
        localStorage.setItem('token', res.token);
        localStorage.setItem('user', JSON.stringify(userObj));
        if (rememberMe) {
          localStorage.setItem('remember_me', 'true');
        }
        return;
      }
      throw new Error(res.message || 'فشل تسجيل الدخول');
    } catch (localErr: any) {
      if (localErr.response?.data?.message) {
        throw new Error(localErr.response.data.message);
      }
      throw localErr;
    }
  };

  const logout = async () => {
    setToken(null);
    setUser(null);
    localStorage.removeItem('token');
    localStorage.removeItem('user');
    window.location.href = '/login';
  };

  return (
    <AuthContext.Provider value={{ user, token, isLoading, login, logout }}>
      {children}
    </AuthContext.Provider>
  );
};

export const useAuth = () => {
  const context = useContext(AuthContext);
  if (!context) {
    const savedUser = localStorage.getItem('user');
    const user = savedUser ? JSON.parse(savedUser) : null;
    const token = localStorage.getItem('token');
    return {
      user,
      token,
      isLoading: false,
      login: async () => {},
      logout: () => {
        localStorage.removeItem('token');
        localStorage.removeItem('user');
        window.location.href = '/login';
      },
    };
  }
  return context;
};
