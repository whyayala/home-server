FROM python:3.9.19-alpine3.19

RUN python -m pip install --upgrade pip
RUN pip install tidal-dl
