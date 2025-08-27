#!/usr/bin/env python

"""
Test file with vulnerable dependencies to verify Snyk scanner.
DO NOT USE IN PRODUCTION - For testing only.
"""

# This imports a known vulnerable version of flask
# Snyk should detect this vulnerability
import flask  # Flask <2.0.0 has vulnerabilities

app = flask.Flask(__name__)

@app.route('/')
def index():
    return 'Hello World!'

if __name__ == '__main__':
    app.run(debug=True)
