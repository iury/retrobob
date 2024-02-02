/* eslint-env node */

module.exports = {
  env: { browser: true, es2020: true },
  extends: ['eslint:recommended', 'plugin:prettier/recommended'],
  plugins: ['prettier'],
  parserOptions: { ecmaVersion: 'latest', sourceType: 'module' },
  rules: {
    'prettier/prettier': 'error',
  },
}
