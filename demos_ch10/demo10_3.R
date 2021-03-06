# Bayesian data analysis
# Aki Vehtari <Aki.Vehtari@aalto.fi>
# Markus Paasiniemi <Markus.Paasiniemi@aalto.fi>

library(ggplot2)
library(gridExtra)
library(grid)
library(tidyr)
library(MASS)

# Normal approximaton for Bioassay model.

# Bioassay data, (BDA3 page 86)
df1 <- data.frame(
  x = c(-0.86, -0.30, -0.05, 0.73),
  n = c(5, 5, 5, 5),
  y = c(0, 1, 3, 5)
)

# compute the posterior density in a grid
#  - usually should be computed in logarithms!
#  - with alternative prior, check that range and spacing of A and B
#    are sensible

A = seq(-4, 8, length.out = 100)
B = seq(-10, 40, length.out = 100)

# make vectors that contain all pairwise combinations of A and B
cA <- rep(A, each = length(B))
cB <- rep(B, length(A))

# a helper function to calculate the log likelihood
logl <- function(df, a, b)
  df['y']*(a + b*df['x']) - df['n']*log1p(exp(a + b*df['x']))

# calculate likelihoods: apply logl function for each observation
# ie. each row of data frame of x, n and y
p <- apply(df1, 1, logl, cA, cB) %>% rowSums() %>% exp()


# sample from the grid (with replacement)
nsamp <- 1000
samp_indices <- sample(length(p), size = nsamp,
                       replace = T, prob = p/sum(p))

samp_A <- cA[samp_indices[1:nsamp]]
samp_B <- cB[samp_indices[1:nsamp]]
# add random jitter, see BDA3 p. 76
samp_A <- samp_A + runif(nsamp, (A[1] - A[2])/2, (A[2] - A[1])/2)
samp_B <- samp_B + runif(nsamp, (B[1] - B[2])/2, (B[2] - B[1])/2)

# samples of LD50
samp_ld50 <- -samp_A/samp_B

# limits for the plots
xl <- c(-2, 8)
yl <- c(-10, 40)

# create a plot of the posterior density
pos <- ggplot(data = data.frame(cA ,cB, p), aes(x = cA, y = cB)) +
  geom_raster(aes(fill = p, alpha = p), interpolate = T) +
  geom_contour(aes(z = p), colour = 'black', size = 0.2) +
  coord_cartesian(xlim = xl, ylim = yl) +
  labs(x = 'alpha', y = 'beta') +
  scale_fill_gradient(low = 'yellow', high = 'red', guide = F) +
  scale_alpha(range = c(0, 1), guide = F)

# plot of the samples
sam <- ggplot(data = data.frame(samp_A, samp_B)) +
  geom_point(aes(samp_A, samp_B), color = 'blue', size = 0.3) +
  coord_cartesian(xlim = xl, ylim = yl) +
  labs(x = 'alpha', y = 'beta')

# plot of the histogram of LD50
his <- ggplot() +
  geom_histogram(aes(samp_ld50), binwidth = 0.1,
                 fill = 'steelblue', color = 'black') +
  coord_cartesian(xlim = c(-0.8, 0.8)) +
  labs(x = 'LD50 = -alpha/beta')

# define the function to be optimized
bioassayfun <- function(w, df) {
  z <- w[1] + w[2]*df$x
  -sum(df$y*(z) - df$n*log1p(exp(z)))
}


# initial guess
w0 <- c(0,0)
optim_res <- optim(w0, bioassayfun, gr = NULL, df1, hessian = T)
w <- optim_res$par
S <- solve(optim_res$hessian)

# multivariate normal probability density function
dmvnorm <- function(x, mu, sig)
  exp(-0.5*(length(x)*log(2*pi) + log(det(sig)) + (x-mu)%*%solve(sig, x-mu)))

# evaluate likelihood at points (cA,cB) 
# this is just for illustration and would not be needed otherwise
p <- apply(cbind(cA, cB), 1, dmvnorm, w, S)

# sample from the multivariate normal 
samp_norm <- mvrnorm(nsamp, w, S)

# samples of LD50 conditional beta > 0
# Normal approximation does not take into account that the posterior
# is not symmetric and that there is very low density for negative
# beta values. Based on the draws from the normal approximation
# is is estimated that there is about 5% probability that beta is negative!
bpi <- samp_norm[,2] > 0
samp_norm_ld50 <- -samp_norm[bpi,1]/samp_norm[bpi,2]

# create a plot of the posterior density
pos_norm <- ggplot(data = data.frame(cA ,cB, p), aes(x = cA, y = cB)) +
  geom_raster(aes(fill = p, alpha = p), interpolate = T) +
  geom_contour(aes(z = p), colour = 'black', size = 0.2) +
  coord_cartesian(xlim = xl, ylim = yl) +
  labs(x = 'alpha', y = 'beta') +
  scale_fill_gradient(low = 'yellow', high = 'red', guide = F) +
  scale_alpha(range = c(0, 1), guide = F)

# plot of the samples
sam_norm <- ggplot(data = data.frame(samp_A=samp_norm[,1], samp_B=samp_norm[,2])) +
  geom_point(aes(samp_A, samp_B), color = 'blue', size = 0.3) +
  coord_cartesian(xlim = xl, ylim = yl) +
  labs(x = 'alpha', y = 'beta')

# plot of the histogram of LD50
his_norm <- ggplot() +
  geom_histogram(aes(samp_norm_ld50), binwidth = 0.1,
                 fill = 'steelblue', color = 'black') +
  coord_cartesian(xlim = c(-0.8, 0.8)) +
  labs(x = 'LD50 = -alpha/beta, beta > 0')

# importance sampling
# multivariate normal log probability density function
ldmvnorm <- function(x, mu, sig)
  (-0.5*(length(x)*log(2*pi) + log(det(sig)) + (x-mu)%*%solve(sig, x-mu)))
lg <- apply(samp_norm, 1, ldmvnorm, w, S)
lp <- apply(df1, 1, logl, samp_norm[,1], samp_norm[,2]) %>% rowSums()
lw <- lp-lg
library(loo)
psis <- psislw(lw)
pis <- exp(psis$lw_smooth)
# Pareto diagnostics
print(psis$pareto_k)

# Importance sampling weights could be used to weight different expectations directly, but 
# for visualisation and easy computation of LD50 histogram, we use resampling importance sampling.
samp_indices <- sample(length(pis), size = nsamp,
                       replace = T, prob = pis)

rissamp_A <- samp_norm[samp_indices,1]
rissamp_B <- samp_norm[samp_indices,2]
# add random jitter, see BDA3 p. 76
rissamp_A <- rissamp_A + runif(nsamp, (A[1] - A[2])/2, (A[2] - A[1])/2)
rissamp_B <- rissamp_B + runif(nsamp, (B[1] - B[2])/2, (B[2] - B[1])/2)

# samples of LD50 
rissamp_ld50 <- -rissamp_A/rissamp_B

# plot of the samples
sam_ris <- ggplot(data = data.frame(rissamp_A, rissamp_B)) +
  geom_point(aes(rissamp_A, rissamp_B), color = 'blue', size = 0.3) +
  coord_cartesian(xlim = xl, ylim = yl) +
  labs(x = 'alpha', y = 'beta')

# plot of the histogram of LD50
his_ris <- ggplot() +
  geom_histogram(aes(rissamp_ld50), binwidth = 0.1,
                 fill = 'steelblue', color = 'black') +
  coord_cartesian(xlim = c(-0.8, 0.8)) +
  labs(x = 'LD50 = -alpha/beta')


# combine the plots
blank <- grid.rect(gp=gpar(col="white"))
grid.arrange(pos, sam, his, pos_norm, sam_norm, his_norm, blank, sam_ris, his_ris, ncol=3)
