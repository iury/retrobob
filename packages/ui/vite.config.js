import process from 'node:process'
import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react-swc'
import { plugin as mdPlugin, Mode } from 'vite-plugin-markdown'

export default defineConfig({
  server: {
    headers: {
      'Cross-Origin-Opener-Policy': 'same-origin',
      'Cross-Origin-Embedder-Policy': 'require-corp',
    },
  },
  plugins: [react(), mdPlugin({ mode: Mode.HTML })],
  define: {
    __APP_VERSION__: JSON.stringify(process.env.VERSION.match(/^\d+\.\d+/)[0]),
  },
})
