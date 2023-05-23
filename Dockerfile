ARG PY_VER=3.10
ARG OS_VER=jammy
ARG BASE_DATE=20230328

ARG BUILD_TAG=${PY_VER}-${OS_VER}-build-${BASE_DATE}
ARG RUN_TAG=${PY_VER}-${OS_VER}-run-${BASE_DATE}

FROM balenalib/raspberrypi4-64-ubuntu-python:${BUILD_TAG} as userland
# install deps to build userland
RUN install_packages \
    cmake

# copy userland git and build
RUN mkdir -p /usr/local/src/userland
COPY sources/userland /usr/local/src/userland
WORKDIR /usr/local/src/userland
RUN ./buildme --aarch64

FROM balenalib/raspberrypi4-64-ubuntu-python:${BUILD_TAG} as donkeycar-build

WORKDIR /app
# Sets utf-8 encoding for Python et al
ENV LANG=C.UTF-8
# Turns off writing .pyc files; superfluous on an ephemeral container.
ENV PYTHONDONTWRITEBYTECODE=1
# Seems to speed things up
ENV PYTHONUNBUFFERED=1
# to make picamera build in docker
ENV READTHEDOCS=True

# Ensures that the python and pip executables used
# in the image will be those from our virtualenv.
ENV PATH="/venv/bin:$PATH"
# Setup the virtualenv
RUN python -m venv /venv \
    && /venv/bin/pip install wheel
COPY sources/donkeycar /donkeycar

WORKDIR /donkeycar
RUN /venv/bin/pip wheel --no-cache-dir \
    -w /wheels/ \
    -e /donkeycar/.[pi]

ARG CAR_DIR=/root/car

FROM balenalib/raspberrypi4-64-ubuntu-python:${RUN_TAG} as carrunner

# Install runtime dependencies
RUN pip install --no-cache-dir \
    tensorflow==2.12 \
    opencv-python-headless

# ensure we have userland
COPY --from=userland /opt/vc/ /usr/

# install from wheels to minimize size
COPY --from=donkeycar-build /wheels /tmp/wheels
RUN pip install --no-cache-dir \
    --no-index \
    --find-links /tmp/wheels \
    donkeycar[pi] \
    && rm -rf /tmp/wheels

# test to ensure that donkey binary starts
RUN donkey createcar --path /tmp/mycar

# run openssh server for interactive use
RUN install_packages openssh-server
RUN mkdir /var/run/sshd \
    && sed 's@session\s*required\s*pam_loginuid.so@session optional pam_loginuid.so@g' -i /etc/pam.d/sshd \
    && mkdir /root/.ssh/ \
    && echo "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHnofKbghuYBeVxHxJiOfBsiSAiVMyRvlorSncmKyS8x shermanm@msh-laptop" > /root/.ssh/authorized_keys
EXPOSE 22
EXPOSE 8886
EXPOSE 8887

# Copy prebuilt car into container
COPY cars/chiaracer/myconfig.py /root/default_config.py
RUN mkdir ${CAR_DIR}
WORKDIR ${CAR_DIR}

# Start car in webui control mode
# CMD python manage.py drive
# CMD "/bin/bash"
CMD ["/usr/sbin/sshd", "-D"]


