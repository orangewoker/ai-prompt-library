import axios from 'axios'
const api = axios.create({ baseURL: import.meta.env.VITE_API_BASE || '' })
api.interceptors.request.use(config => { const token = localStorage.getItem('vpl_token'); if (token) config.headers.Authorization = `Bearer ${token}`; return config })
api.interceptors.response.use(response => response, error => {
  if (error.response?.status === 401 && !error.config?.url?.includes('/auth/login')) {
    localStorage.removeItem('vpl_token')
    localStorage.removeItem('vpl_user')
    window.dispatchEvent(new CustomEvent('vpl-auth-expired'))
  }
  return Promise.reject(error)
})
export default api
