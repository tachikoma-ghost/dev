FROM reactnativecommunity/react-native-android:latest
RUN curl -fsSL https://go.dev/dl/go1.23.5.linux-amd64.tar.gz -o /tmp/go.tar.gz && \
	    tar -xzf /tmp/go.tar.gz -C /usr/local && \
	    rm /tmp/go.tar.gz
ENV PATH=$PATH:/usr/local/go/bin
