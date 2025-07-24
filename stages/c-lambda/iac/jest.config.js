module.exports = {
  testEnvironment: 'node',
  roots: ['<rootDir>/test'],
  testMatch: ['**/*.test.ts'],
  transform: {
    '^.+\\.tsx?$': 'ts-jest'
  },
  collectCoverageFrom: [
    '**/*.(t|j)s'
  ],
  coverageDirectory: 'coverage',
  testPathIgnorePatterns: [
    '/node_modules/'
  ]
}; 